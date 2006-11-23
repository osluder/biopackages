#$Id: Makefile,v 1.21 2006/11/23 00:05:32 bpbuild Exp $
LN_S=ln -s
PERL=/usr/bin/perl
RM_RF=rm -rf
RM_I=rm -i
RPMBUILD=/usr/bin/rpmbuild
SYNCHOST=neuron.genomics.ctrl.ucla.edu
RECURSIVE_BUILD=bin/resolve_deps.pl

####################################
#stuff for initial environment setup
prep ::
	echo '' >> ~/.rpmmacros
	$(RM_I) ~/.rpmmacros
	$(PERL) bin/rpmmacros.pl > ~/.rpmmacros
	echo 'for d in tmp SETTINGS SOURCES SRPMS BUILD RPMS/i386 RPMS/noarch RPMS/ppc RPMS/ppc64 RPMS/x86_64; do mkdir -p $${d}; done' | /bin/bash
	$(MAKE) sources
	$(MAKE) settings

####################################
#main build targets
# triggers a .spec and .built file for each spec file on each target platform
# also summarizes the build status of each to a log file
cluster_buildall ::
	echo 'for i in SPECS/*.spec.in; do $(MAKE) $${i/.spec.in/.cbuilt}; done' | /bin/bash 

# creates an HTML output report summarizing the build status of each package based on logs
cluster_build_report ::
	echo 'for i in SETTINGS/*; do echo "$$i/\n"; done' | /bin/bash #LEFT OFF HERE

all :: specs

buildall :: specs
	echo 'for i in SPECS/*.spec; do $(MAKE) $${i/.spec/.built}; done' | /bin/bash

buildclean ::
	$(RM_RF) SPECS/*.built

sources ::
	perl -e '(-e "/home/bpbuild/SOURCES.large") ? print "make symlink\n" : print "make rsync\n"' | /bin/bash

settings ::
	perl -e '(-e "/home/bpbuild/SETTINGS") ? print "make symlink_settings\n" : print "make rsync_settings"' | /bin/bash

specs ::
	echo 'for i in SPECS/*.spec.in; do $(MAKE) $${i/.spec.in/.spec}; done' | /bin/bash

####################################
#extension rules
# LEFT OFF HERE
# rbuilt is a target for the local machine that calls the recursive build program (resolve_deps)
%.rbuilt : %.spec
	echo '$(RECURSIVE_BUILD) --spec $(subst .spec,,$<)'
	touch $@
	#FIXME: change echo to run

# cbuilt is a qsub script that is called to produce a .spec and .built file on each platform
%.cbuilt : %.spec.in
	echo 'for i in SETTINGS/*; do echo -e "#!/bin/bash\n\n$(MAKE) $(subst .spec.in,.rbuilt,$<)\n" > $(subst .spec.in,,$<)_$${i#SETTINGS/}.sh; echo "qsub -cwd -o /dev/null -e /dev/null -q $${i#SETTINGS/}.q $(subst .spec.in,,$<)_$${i#SETTINGS/}.sh"; done' | /bin/bash
	echo 'for i in SETTINGS/*.i386; do file=$${i#SETTINGS/}; file=$${file%.i386}; echo -e "#!/bin/bash\n\n$(MAKE) $(subst .spec.in,.rbuilt,$<)\n" > $(subst .spec.in,,$<)_$$file.noarch.sh; echo "qsub -cwd -o /dev/null -e /dev/null -q $$file.noarch.q $(subst .spec.in,,$<)_$$file.noarch.sh"; done' | /bin/bash
	touch $@
	#FIXME: right now assuming everything is arch, need to qsub to noarch when appropriate
	#FIXME: change the echo qsub to actual call
	#FIXME: Reroute stderr/out to better log file later

%.built : %.spec
	perl -e '($$f,$$e,$$d,$$c,$$b,$$a)=localtime();print "#rpmbuild begin ".join(":",$$a+1900,$$b,$$c,$$d,$$e,$$f),"\n"' > $@
	($(RPMBUILD) -ba $< 2>&1 >> $@ && \
	perl -e '($$f,$$e,$$d,$$c,$$b,$$a)=localtime();print "#rpmbuild end ".join(":",$$a+1900,$$b,$$c,$$d,$$e,$$f),"\n"' >> $@) || $(RM_RF) $@

%.clean :
	find . -name "$(@:.clean=)*" -exec $(RM_RF) {} \;

%.pm :
	# bail out if locked, or if special and needs manual build
	`echo 'if [ -f $(@:.pm=.pmlock) ]; then exit 1 ; else exit 0 ; fi' | /bin/bash`;
	`echo 'if [ -f SPECS/$(@:.pm=.spec) ]; then exit 1 ; else exit 0 ; fi' | /bin/bash`;

	# lock
	touch $(@:.made=.lock);
	$(PERL) bin/pmfetch.pl $@ 2>$(@:.pm=.pmlog);

	#this could be brittle on make -jN where N > 1
	$(PERL) bin/pmbuild.pl SPECS/`ls -rt1 SPECS/ | tail -1` $(@:.pm=);

	# cleanup and unlock
	$(RM) *debuginfo*;
	$(RM) $(@:.pm=.pmlock);

	#check dependencies and recurse
	/bin/bash bin/pmcheckdeps.sh `ls -rt1 SPECS/ | tail -1` $(TARGETARCH);

	#mark it done
	touch $@;

%.spec : %.spec.in
	cat $< | $(PERL) bin/in2spec.pl > $@

####################################
#synlink/rsync targets to maintain SETTINGS
#this dir structure also has the logs dir
symlink_settings ::
	cd SETTINGS; ln -s /home/bpbuild/SETTINGS/* .; cd ..

rsync_settings : rsync_settings_down rsync_settings_up
rsync_settings_down ::
	rsync -avr $(SYNCHOST):/home/bpbuild/SETTINGS/ ./SETTINGS
rsync_settings_up ::
	rsync -avr ./SETTINGS/ $(SYNCHOST):/home/bpbuild/SETTINGS

#symlink/rsync targets to maintain SOURCES/
symlink : symlink_clean symlink_small symlink_large
symlink_clean : sync_clean

symlink_large ::
	ln -s ~bpbuild/SOURCES.large/* ./SOURCES/

symlink_small ::
	ln -s ~bpbuild/SOURCES.small/* ./SOURCES/

rsync :		sync_clean rsync_down rsync_up
rsync_down :	sync_clean rsync_down_small rsync_down_large
rsync_up :	sync_clean rsync_up_small rsync_up_large
rsync_small :	sync_clean rsync_down_small rsync_up_small
rsync_large :	sync_clean rsync_down_large rsync_up_large

sync_clean ::
	@if [[ `find SOURCES/ -type f | grep -vw CVS | wc -l` > 0 ]]; then echo "Move your files from SOURCES/ to one of ~bpbuild/SOURCES.{large,small}"; exit 1; fi
	@find SOURCES/ -type l | grep -vw SOURCES/ | grep -vw SOURCES/CVS | xargs rm -rf
	@find SOURCES/ -type d | grep -vw SOURCES/ | grep -vw SOURCES/CVS | xargs rm -rf

rsync_down_large ::
	rsync -av $(SYNCHOST):/home/bpbuild/SOURCES.large/ ./SOURCES.large
	cd SOURCES; ln -s ../SOURCES.large/* .;	cd ..

rsync_down_small ::
	rsync -av $(SYNCHOST):/home/bpbuild/SOURCES.small/ ./SOURCES.small
	cd SOURCES; ln -s ../SOURCES.small/* .; cd ..

rsync_up_large ::
	rsync -av ./SOURCES.large/ $(SYNCHOST):/home/bpbuild/SOURCES.large

rsync_up_small ::
	rsync -av ./SOURCES.small/ $(SYNCHOST):/home/bpbuild/SOURCES.small

