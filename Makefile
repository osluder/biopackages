#$Id: Makefile,v 1.37 2006/12/05 23:44:06 bpbuild Exp $
LN_S=ln -s
PERL=/usr/bin/perl
RM_RF=rm -rf
RM_I=rm -i
RPMBUILD=/usr/bin/rpmbuild
SYNCHOST=neuron.genomics.ctrl.ucla.edu
RECURSIVE_BUILD=bin/resolve_deps.pl

# FIXME:
# * the cvsupdate target may not actually work (no rsh var set? can't login?)

####################################
#stuff for initial environment setup
prep ::
	$(PERL) bin/rpmmacros.pl > ~/.rpmmacros
	echo 'for d in tmp SETTINGS SOURCES SRPMS BUILD RPMS/i386 RPMS/noarch RPMS/ppc RPMS/ppc64 RPMS/x86_64; do mkdir -p $${d}; done' | /bin/bash
	$(MAKE) sources
	$(MAKE) settings

####################################
#main build targets
# triggers a .spec and .built file for each spec file on each target platform
# also summarizes the build status of each to a log file
# FIXME: add individual targets so you can build all/a package on a certain queue
cluster_buildall ::
	$(MAKE) buildclean
	$(MAKE) prep
	cvs update
	$(MAKE) cluster_buildclean
	$(MAKE) cluster_cvsupdate
	echo 'for i in SPECS/*.spec.in; do $(MAKE) $${i/.spec.in/.cbuilt}; done' | /bin/bash 

cluster_buildclean ::
	echo 'for i in SETTINGS/*; do spec=$(subst .spec.in,,$<); spec=$${spec#SPECS/}; spec=$${spec}; file=$${i#SETTINGS/}; distro=$${file%.*}; arch=$${file#*.}; echo -e "#!/bin/bash\n\n$(MAKE) buildclean\n" > SETTINGS/$$file/SCRIPTS/cluster_buildclean.sh; qsub -cwd -o SETTINGS/$$file/LOGS/cluster_buildclean.stdout -e SETTINGS/$$file/LOGS/cluster_buildclean.stderr -q $$file.q SETTINGS/$$file/SCRIPTS/cluster_buildclean.sh; done' | /bin/bash

cluster_cvsupdate ::
	echo 'for i in SETTINGS/*; do spec=$(subst .spec.in,,$<); spec=$${spec#SPECS/}; spec=$${spec}; file=$${i#SETTINGS/}; distro=$${file%.*}; arch=$${file#*.}; echo -e "#!/bin/bash\n\ncvs update\n" > SETTINGS/$$file/SCRIPTS/cluster_cvsupdate.sh; qsub -cwd -o SETTINGS/$$file/LOGS/cluster_cvsupdate.stdout -e SETTINGS/$$file/LOGS/cluster_cvsupdate.stderr -q $$file.q SETTINGS/$$file/SCRIPTS/cluster_cvsupdate.sh; done' | /bin/bash

# creates an HTML output report summarizing the build status of each package based on logs
# FIXME: this needs to be implemented
cluster_build_report ::
	echo 'for i in SETTINGS/*; do echo "$$i/\n"; done' | /bin/bash 

cluster_report ::
	sudo mkdir -p /var/www/html/biopackages_report
	perl bin/build_report.pl --dir SETTINGS --outdir REPORTS --format html
	sudo cp REPORTS/green.gif REPORTS/red.gif REPORTS/index.html /var/www/html/biopackages_report
	sudo ln -s /usr/src/biopackages/SETTINGS /var/www/html/biopackages_report/SETTINGS

all :: specs

buildall :: specs
	echo 'for i in SPECS/*.spec; do $(MAKE) $${i/.spec/.built}; done' | /bin/bash

buildclean ::
	$(RM_RF) SPECS/*.built
	$(RM_RF) SPECS/*.cbuilt
	$(RM_RF) SPECS/*.rbuilt

sources ::
	perl -e '(-e "/home/bpbuild/SOURCES.large") ? print "make symlink\n" : print "make rsync\n"' | /bin/bash

settings ::
	perl -e '(-e "/home/bpbuild/SETTINGS") ? print "make symlink_settings\n" : print "make rsync_settings"' | /bin/bash

specs ::
	echo 'for i in SPECS/*.spec.in; do $(MAKE) $${i/.spec.in/.spec}; done' | /bin/bash

####################################
#extension rules
# rbuilt is a target for the local machine that calls the recursive build program (resolve_deps)
# FIXME: probably don't need verbose here
%.rbuilt : %.spec
	echo 'spec=$(subst .spec,,$<); spec=$${spec#SPECS/}; perl $(RECURSIVE_BUILD) --verbose --spec $$spec' | /bin/bash
	touch $@

# cbuilt is a qsub script that is called to produce a .spec and .built file on each platform
# FIXME: remove buildclean, only needed for testing
# FIXME: remove cvs update/make prep when in production (cluster_buildall already will call this)
%.cbuilt : %.spec.in
	echo 'for i in SETTINGS/*; do spec=$(subst .spec.in,,$<); spec=$${spec#SPECS/}; spec=$${spec}; file=$${i#SETTINGS/}; distro=$${file%.*}; arch=$${file#*.}; rm SETTINGS/$$file/LOGS/$$spec.*; echo -e "#!/bin/bash\n\ncvs update\nmake prep\n$(MAKE) buildclean\n$(MAKE) $(subst .spec.in,.rbuilt,$<)\n" > SETTINGS/$$file/SCRIPTS/$$spec.sh; echo "qsub -cwd -o SETTINGS/$$file/LOGS/$$spec.stdout -e SETTINGS/$$file/LOGS/$$spec.stderr -q $$file.q SETTINGS/$$file/SCRIPTS/$$spec.sh"; qsub -cwd -o SETTINGS/$$file/LOGS/$$spec.stdout -e SETTINGS/$$file/LOGS/$$spec.stderr -q $$file.q SETTINGS/$$file/SCRIPTS/$$spec.sh; done' | /bin/bash
	touch $@

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

