# 
#   Copyright 2009 Joe Block <jpb@ApesSeekingKnowledge.net>
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

STAMP:=`date +%Y%m%d`
YY:=`date +%Y`
MM:=`date +%m`
DD:=`date +%d`
BUILD_DATE=`date -u "+%Y-%m-%dT%H:%M:%SZ"`

# mai plist haz a flavor
PLIST_FLAVOR=plist
PACKAGE_PLIST=.package.plist

PACKAGE_TARGET_OS=10.4
PLIST_TEMPLATE=prototype.plist
TITLE=CHANGE_ME
REVERSE_DOMAIN=com.replaceme
PACKAGE_ID=${REVERSE_DOMAIN}.${TITLE}

# Set PACKAGE_VERSION in your Makefile if you don't want version set to
# today's date
PACKAGE_VERSION=${STAMP}
PACKAGE_MAJOR_VERSION=${YY}
PACKAGE_MINOR_VERSION=${MM}${DD}

# Set PACKAGE_NAME in your Makefile if you don't want it to be TITLE-PACKAGEVERSION.
PACKAGE_NAME=${TITLE}-${PACKAGE_VERSION}
PACKAGE_FILE=${PACKAGE_NAME}.pkg
DMG_NAME=${PACKAGE_NAME}.dmg
ZIP_NAME=${PACKAGE_FILE}.zip

# Only use Apple tools for file manipulation, or deal with a world of pain
# when your resource forks get munched.  This is particularly important on
# 10.6 since it stores compressed binaries in the resource fork.
TAR=/usr/bin/tar
CP=/bin/cp
INSTALL=/usr/bin/install
DITTO=/usr/bin/ditto
UNZIP=/usr/bin/unzip
PB=/usr/libexec/PlistBuddy

PACKAGEMAKER=/Developer/usr/bin/packagemaker

# Must be on an HFS+ filesystem. Yes, I know some network servers will do
# their best to preserve the resource forks, but it isn't worth the aggravation
# to fight with them.
LUGGAGE_TMP=/tmp/the_luggage
SCRATCH_D=${LUGGAGE_TMP}/${PACKAGE_NAME}

SCRIPT_D=${SCRATCH_D}/scripts
RESOURCE_D=${SCRATCH_D}/resources
WORK_D=${SCRATCH_D}/root
PAYLOAD_D=${SCRATCH_D}/payload

# packagemaker parameters
#
# packagemaker will helpfully apply the permissions it finds on the system
# if one of the files in the payload exists on the disk, rather than the ones
# you've carefully set up in the package root, so I turn that crap off with
# --no-recommend. You can disable this by overriding PM_EXTRA_ARGS in your
# package's Makefile.

PM_EXTRA_ARGS=--verbose --no-recommend --no-relocate

# Override if you want to require a restart after installing your package.
PM_RESTART=None
PAYLOAD=

# hdiutil parameters
#
# hdiutil will create a compressed disk image with the UDZO and UDBZ formats,
# or a bland, uncompressed, read-only image with UDRO. Wouldn't you rather
# trade a little processing time for some disk savings now that you can make
# packages and images with reckless abandon?
#
# The UDZO format is selected as the default here for compatibility, but you
# can override it to achieve higher compression. If you want to switch away
# from UDZO, it is probably best to override DMG_FORMAT in your makefile.
#
# Format notes:
# The UDRO format is an uncompressed, read-only disk image that is compatible
# with Mac OS X 10.0 and later.
# The UDZO format is gzip-based, defaults to gzip level 1, and is compatible
# with Mac OS X 10.2 and later.
# The UDBZ format is bzip2-based and is compatible with Mac OS X 10.4 and later.

DMG_FORMAT_CODE=UDZO
ZLIB_LEVEL=9
DMG_FORMAT_OPTION=-imagekey zlib-level=${ZLIB_LEVEL}
DMG_FORMAT=${DMG_FORMAT_CODE} ${DMG_FORMAT_OPTION}

# Set .PHONY declarations so things don't break if someone has files in
# their workdir with the same names as our special stanzas

.PHONY: clean
.PHONY: debug
.PHONY: dmg
.PHONY: grind_package
.PHONY: local_pkg
.PHONY: package_root
.PHONY: payload_d
.PHONY: pkg
.PHONY: scratchdir
.PHONY: superclean

# Convenience variables
USER_TEMPLATE=${WORK_D}/System/Library/User\ Template
USER_TEMPLATE_PREFERENCES=${USER_TEMPLATE}/English.lproj/Library/Preferences
USER_TEMPLATE_PICTURES=${USER_TEMPLATE}/English.lproj/Pictures
USER_TEMPLATE_APPLICATION_SUPPORT=${USER_TEMPLATE}/English.lproj/Library/Application\ Support

# target stanzas

help:
	@-echo
	@-echo "make clean - clean up work files."
	@-echo "make dmg - roll a pkg, then stuff it into a dmg file."
	@-echo "make zip - roll a pkg, then stuff it into a zip file."
	@-echo "make pkg - roll a pkg."
	@-echo

# set up some work directories

payload_d:
	@sudo mkdir -p ${PAYLOAD_D}

package_root:
	@sudo mkdir -p ${WORK_D}

# packagemaker chokes if the pkg doesn't contain any payload, making script-only
# packages fail to build mysteriously if you don't remember to include something
# in it, so we're including the /usr/local directory, since it's harmless.
scriptdir: l_usr_local
	@sudo mkdir -p ${SCRIPT_D}

resourcedir:
	@sudo mkdir -p ${RESOURCE_D}

scratchdir:
	@sudo mkdir -p ${SCRATCH_D}

# user targets

clean:
	@sudo rm -fr ${SCRATCH_D} .luggage.pkg.plist ${PACKAGE_PLIST}

superclean:
	@sudo rm -fr ${LUGGAGE_TMP}

dmg: scratchdir compile_package
	@echo "Wrapping ${PACKAGE_NAME}..."
	@sudo hdiutil create -volname ${PACKAGE_NAME} \
		-srcfolder ${PAYLOAD_D} \
		-uid 99 -gid 99 \
		-ov \
		-format ${DMG_FORMAT} \
		${DMG_NAME}

zip: scratchdir compile_package
	@echo "Zipping ${PACKAGE_NAME}..."
	@${DITTO} -c -k \
		--noqtn --noacl \
		--sequesterRsrc \
		${PAYLOAD_D} \
		${ZIP_NAME}
		
modify_packageroot:
	@echo "If you need to override permissions or ownerships, override modify_packageroot in your Makefile"

prep_pkg:
	@make clean
	@make compile_package

pkg: prep_pkg
	@make local_pkg

pkgls: prep_pkg
	@echo
	@echo
	lsbom -p fmUG ${PAYLOAD_D}/${PACKAGE_FILE}/Contents/Archive.bom

#
payload: payload_d package_root scratchdir scriptdir resourcedir
	make ${PAYLOAD}
	@-echo

compile_package: payload .luggage.pkg.plist
	@make modify_packageroot
	@-sudo rm -fr ${PAYLOAD_D}/${PACKAGE_FILE}
	@echo "Creating ${PAYLOAD_D}/${PACKAGE_FILE}"
	sudo ${PACKAGEMAKER} --root ${WORK_D} \
		--id ${PACKAGE_ID} \
		--filter DS_Store \
		--target ${PACKAGE_TARGET_OS} \
		--title ${TITLE} \
		--info ${SCRATCH_D}/luggage.pkg.plist \
		--scripts ${SCRIPT_D} \
		--resources ${RESOURCE_D} \
		--version ${PACKAGE_VERSION} \
		${PM_EXTRA_ARGS} --out ${PAYLOAD_D}/${PACKAGE_FILE}

${PACKAGE_PLIST}: /usr/local/share/luggage/prototype.plist
# override this stanza if you have a different plist you want to use as
# a custom local template.
	@cat /usr/local/share/luggage/prototype.plist > ${PACKAGE_PLIST}

.luggage.pkg.plist: ${PACKAGE_PLIST}
	@cat ${PACKAGE_PLIST} | \
		sed "s/{DD}/${DD}/g" | \
		sed "s/{MM}/${MM}/g" | \
		sed "s/{YY}/${YY}/g" | \
		sed "s/{PACKAGE_MAJOR_VERSION}/${PACKAGE_MAJOR_VERSION}/g" | \
		sed "s/{PACKAGE_MINOR_VERSION}/${PACKAGE_MINOR_VERSION}/g" | \
		sed "s/{BUILD_DATE}/${BUILD_DATE}/g" | \
		sed "s/{PACKAGE_ID}/${PACKAGE_ID}/g" | \
		sed "s/{PACKAGE_VERSION}/${PACKAGE_VERSION}/g" | \
		sed "s/{PM_RESTART}/${PM_RESTART}/g" | \
	        sed "s/{PLIST_FLAVOR}/${PLIST_FLAVOR}/g" \
		> .luggage.pkg.plist
	@sudo ${CP} .luggage.pkg.plist ${SCRATCH_D}/luggage.pkg.plist
	@rm .luggage.pkg.plist ${PACKAGE_PLIST}

local_pkg:
	@${CP} -R ${PAYLOAD_D}/${PACKAGE_FILE} .

# Target directory rules

l_root: package_root
	@sudo mkdir -p ${WORK_D}
	@sudo chmod 755 ${WORK_D}
	@sudo chown root:admin ${WORK_D}

l_private: l_root
	@sudo mkdir -p ${WORK_D}/private
	@sudo chown -R root:wheel ${WORK_D}/private
	@sudo chmod -R 755 ${WORK_D}/private

l_private_etc: l_private
	@sudo mkdir -p ${WORK_D}/private/etc
	@sudo chown -R root:wheel ${WORK_D}/private/etc
	@sudo chmod -R 755 ${WORK_D}/private/etc

l_etc_hooks: l_private_etc
	@sudo mkdir -p ${WORK_D}/private/etc/hooks
	@sudo chown -R root:wheel ${WORK_D}/private/etc/hooks
	@sudo chmod -R 755 ${WORK_D}/private/etc/hooks

l_etc_openldap: l_private_etc
	@sudo mkdir -p ${WORK_D}/private/etc/openldap
	@sudo chmod 755 ${WORK_D}/private/etc/openldap
	@sudo chown root:wheel ${WORK_D}/private/etc/openldap

l_etc_puppet: l_private_etc
	@sudo mkdir -p ${WORK_D}/private/etc/puppet
	@sudo chown -R root:wheel ${WORK_D}/private/etc/puppet
	@sudo chmod -R 755 ${WORK_D}/private/etc/puppet

l_usr: l_root
	@sudo mkdir -p ${WORK_D}/usr
	@sudo chown -R root:wheel ${WORK_D}/usr
	@sudo chmod -R 755 ${WORK_D}/usr

l_usr_bin: l_usr
	@sudo mkdir -p ${WORK_D}/usr/bin
	@sudo chown -R root:wheel ${WORK_D}/usr/bin
	@sudo chmod -R 755 ${WORK_D}/usr/bin

l_usr_lib: l_usr
	@sudo mkdir -p ${WORK_D}/usr/lib
	@sudo chown -R root:wheel ${WORK_D}/usr/lib
	@sudo chmod -R 755 ${WORK_D}/usr/lib

l_usr_local: l_usr
	@sudo mkdir -p ${WORK_D}/usr/local
	@sudo chown -R root:wheel ${WORK_D}/usr/local
	@sudo chmod -R 755 ${WORK_D}/usr/local

l_usr_local_bin: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/bin
	@sudo chown -R root:wheel ${WORK_D}/usr/local/bin
	@sudo chmod -R 755 ${WORK_D}/usr/local/bin

l_usr_local_lib: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/lib
	@sudo chown -R root:wheel ${WORK_D}/usr/local/lib
	@sudo chmod -R 755 ${WORK_D}/usr/local/lib

l_usr_local_man: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/man
	@sudo chown -R root:wheel ${WORK_D}/usr/local/man
	@sudo chmod -R 755 ${WORK_D}/usr/local/man

l_usr_local_sbin: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/sbin
	@sudo chown -R root:wheel ${WORK_D}/usr/local/sbin
	@sudo chmod -R 755 ${WORK_D}/usr/local/sbin

l_usr_local_share: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/share
	@sudo chown -R root:wheel ${WORK_D}/usr/local/share
	@sudo chmod -R 755 ${WORK_D}/usr/local/share

l_usr_man: l_usr_share
	@sudo mkdir -p ${WORK_D}/usr/share/man
	@sudo chown -R root:wheel ${WORK_D}/usr/share/man
	@sudo chmod -R 0755 ${WORK_D}/usr/share/man

l_usr_man_man1: l_usr_man
	@sudo mkdir -p ${WORK_D}/usr/share/man/man1
	@sudo chown -R root:wheel ${WORK_D}/usr/share/man/man1
	@sudo chmod -R 0755 ${WORK_D}/usr/share/man/man1

l_usr_man_man2: l_usr_man
	@sudo mkdir -p ${WORK_D}/usr/share/man/man2
	@sudo chown -R root:wheel ${WORK_D}/usr/share/man/man2
	@sudo chmod -R 0755 ${WORK_D}/usr/share/man/man2

l_usr_man_man3: l_usr_man
	@sudo mkdir -p ${WORK_D}/usr/share/man/man3
	@sudo chown -R root:wheel ${WORK_D}/usr/share/man/man3
	@sudo chmod -R 0755 ${WORK_D}/usr/share/man/man3

l_usr_man_man4: l_usr_man
	@sudo mkdir -p ${WORK_D}/usr/share/man/man4
	@sudo chown -R root:wheel ${WORK_D}/usr/share/man/man4
	@sudo chmod -R 0755 ${WORK_D}/usr/share/man/man4

l_usr_man_man5: l_usr_man
	@sudo mkdir -p ${WORK_D}/usr/share/man/man5
	@sudo chown -R root:wheel ${WORK_D}/usr/share/man/man5
	@sudo chmod -R 0755 ${WORK_D}/usr/share/man/man5

l_usr_man_man6: l_usr_man
	@sudo mkdir -p ${WORK_D}/usr/share/man/man6
	@sudo chown -R root:wheel ${WORK_D}/usr/share/man/man6
	@sudo chmod -R 0755 ${WORK_D}/usr/share/man/man6

l_usr_man_man7: l_usr_man
	@sudo mkdir -p ${WORK_D}/usr/share/man/man7
	@sudo chown -R root:wheel ${WORK_D}/usr/share/man/man7
	@sudo chmod -R 0755 ${WORK_D}/usr/share/man/man7

l_usr_man_man8: l_usr_man
	@sudo mkdir -p ${WORK_D}/usr/share/man/man8
	@sudo chown -R root:wheel ${WORK_D}/usr/share/man/man8
	@sudo chmod -R 0755 ${WORK_D}/usr/share/man/man8

l_usr_sbin: l_usr
	@sudo mkdir -p ${WORK_D}/usr/sbin
	@sudo chown -R root:wheel ${WORK_D}/usr/sbin
	@sudo chmod -R 755 ${WORK_D}/usr/sbin

l_usr_share: l_usr
	@sudo mkdir -p ${WORK_D}/usr/share
	@sudo chown -R root:wheel ${WORK_D}/usr/share
	@sudo chmod -R 755 ${WORK_D}/usr/share

l_var: l_private
	@sudo mkdir -p ${WORK_D}/private/var
	@sudo chown -R root:wheel ${WORK_D}/private/var
	@sudo chmod -R 755 ${WORK_D}/private/var

l_var_lib: l_var
	@sudo mkdir -p ${WORK_D}/private/var/lib
	@sudo chown -R root:wheel ${WORK_D}/private/var/lib
	@sudo chmod -R 755 ${WORK_D}/private/var/lib

l_var_lib_puppet: l_var_lib
	@sudo mkdir -p ${WORK_D}/private/var/lib/puppet
	@sudo chown -R root:wheel ${WORK_D}/private/var/lib/puppet
	@sudo chmod -R 755 ${WORK_D}/private/var/lib/puppet

l_var_db: l_var
	@sudo mkdir -p ${WORK_D}/private/var/db
	@sudo chown -R root:wheel ${WORK_D}/private/var/db
	@sudo chmod -R 755 ${WORK_D}/private/var/db

l_var_root: l_var
	@sudo mkdir -p ${WORK_D}/private/var/root
	@sudo chown -R root:wheel ${WORK_D}/private/var/root
	@sudo chmod -R 750 ${WORK_D}/private/var/root

l_var_root_Library: l_var_root
	@sudo mkdir -p ${WORK_D}/private/var/root/Library
	@sudo chown -R root:wheel ${WORK_D}/private/var/root/Library
	@sudo chmod -R 700 ${WORK_D}/private/var/root/Library

l_var_root_Library_Preferences: l_var_root_Library
	@sudo mkdir -p ${WORK_D}/private/var/root/Library/Preferences
	@sudo chown -R root:wheel ${WORK_D}/private/var/root/Library/Preferences
	@sudo chmod -R 700 ${WORK_D}/private/var/root/Library/Preferences

l_Applications: l_root
	@sudo mkdir -p ${WORK_D}/Applications
	@sudo chown root:admin ${WORK_D}/Applications
	@sudo chmod 775 ${WORK_D}/Applications

l_Applications_Utilities: l_root
	@sudo mkdir -p ${WORK_D}/Applications/Utilities
	@sudo chown root:admin ${WORK_D}/Applications/Utilities
	@sudo chmod 755 ${WORK_D}/Applications/Utilities

l_Library: l_root
	@sudo mkdir -p ${WORK_D}/Library
	@sudo chown root:admin ${WORK_D}/Library
	@sudo chmod 1775 ${WORK_D}/Library

l_Library_Application_Support: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Application\ Support
	@sudo chown root:admin ${WORK_D}/Library/Application\ Support
	@sudo chmod 775 ${WORK_D}/Library/Application\ Support

l_Library_Application_Support_Adobe: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Application\ Support/Adobe
	@sudo chown root:admin ${WORK_D}/Library/Application\ Support/Adobe
	@sudo chmod 775 ${WORK_D}/Library/Application\ Support/Adobe

l_Library_Desktop_Pictures: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Desktop\ Pictures
	@sudo chown root:admin ${WORK_D}/Library/Desktop\ Pictures
	@sudo chmod 775 ${WORK_D}/Library/Desktop\ Pictures

l_Library_Fonts: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Fonts
	@sudo chown root:admin ${WORK_D}/Library/Fonts
	@sudo chmod 775 ${WORK_D}/Library/Fonts

l_Library_LaunchAgents: l_Library
	@sudo mkdir -p ${WORK_D}/Library/LaunchAgents
	@sudo chown root:wheel ${WORK_D}/Library/LaunchAgents
	@sudo chmod 755 ${WORK_D}/Library/LaunchAgents

l_Library_LaunchDaemons: l_Library
	@sudo mkdir -p ${WORK_D}/Library/LaunchDaemons
	@sudo chown root:wheel ${WORK_D}/Library/LaunchDaemons
	@sudo chmod 755 ${WORK_D}/Library/LaunchDaemons

l_Library_QuickTime: l_Library
	@sudo mkdir -p ${WORK_D}/Library/QuickTime
	@sudo chown root:wheel ${WORK_D}/Library/QuickTime
	@sudo chmod 755 ${WORK_D}/Library/QuickTime

l_Library_Preferences: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Preferences
	@sudo chown root:admin ${WORK_D}/Library/Preferences
	@sudo chmod 775 ${WORK_D}/Library/Preferences

l_Library_Preferences_DirectoryService: l_Library_Preferences
	@sudo mkdir -p ${WORK_D}/Library/Preferences/DirectoryService
	@sudo chown root:admin ${WORK_D}/Library/Preferences/DirectoryService
	@sudo chmod 775 ${WORK_D}/Library/Preferences/DirectoryService

l_Library_PreferencePanes: l_Library
	@sudo mkdir -p ${WORK_D}/Library/PreferencePanes
	@sudo chown root:wheel ${WORK_D}/Library/PreferencePanes
	@sudo chmod 755 ${WORK_D}/Library/PreferencePanes

l_Library_Printers: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Printers
	@sudo chown root:admin ${WORK_D}/Library/Printers
	@sudo chmod 775 ${WORK_D}/Library/Printers

l_Library_Printers_PPDs: l_Library_Printers
	@sudo mkdir -p ${WORK_D}/Library/Printers/PPDs/Contents/Resources
	@sudo chown root:admin ${WORK_D}/Library/Printers/PPDs
	@sudo chmod 775 ${WORK_D}/Library/Printers/PPDs

l_PPDs: l_Library_Printers_PPDs

l_Library_Receipts: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Receipts
	@sudo chown root:admin ${WORK_D}/Library/Receipts
	@sudo chmod 775 ${WORK_D}/Library/Receipts

l_Library_User_Pictures: l_Library
	@sudo mkdir -p ${WORK_D}/Library/User\ Pictures
	@sudo chown root:admin ${WORK_D}/Library/User\ Pictures
	@sudo chmod 775 ${WORK_D}/Library/User\ Pictures

l_Library_CorpSupport: l_Library
	@sudo mkdir -p ${WORK_D}/Library/CorpSupport
	@sudo chown root:admin ${WORK_D}/Library/CorpSupport
	@sudo chmod 775 ${WORK_D}/Library/CorpSupport

l_Library_Python: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Python
	@sudo chown root:admin ${WORK_D}/Library/Python
	@sudo chmod 775 ${WORK_D}/Library/Python

l_Library_Python_26: l_Library_Python
	@sudo mkdir -p ${WORK_D}/Library/Python/2.6
	@sudo chown root:admin ${WORK_D}/Library/Python/2.6
	@sudo chmod 775 ${WORK_D}/Library/Python/2.6

l_Library_Python_26_site_packages: l_Library_Python_26
	@sudo mkdir -p ${WORK_D}/Library/Python/2.6/site-packages
	@sudo chown root:admin ${WORK_D}/Library/Python/2.6/site-packages
	@sudo chmod 775 ${WORK_D}/Library/Python/2.6/site-packages

l_Library_Ruby: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Ruby
	@sudo chown root:admin ${WORK_D}/Library/Ruby
	@sudo chmod 775 ${WORK_D}/Library/Ruby

l_Library_Ruby_Site: l_Library_Ruby
	@sudo mkdir -p ${WORK_D}/Library/Ruby/Site
	@sudo chown root:admin ${WORK_D}/Library/Ruby/Site
	@sudo chmod 775 ${WORK_D}/Library/Ruby/Site

l_Library_Ruby_Site_1_8: l_Library_Ruby_Site
	@sudo mkdir -p ${WORK_D}/Library/Ruby/Site/1.8
	@sudo chown root:admin ${WORK_D}/Library/Ruby/Site/1.8
	@sudo chmod 775 ${WORK_D}/Library/Ruby/Site/1.8

l_Library_StartupItems: l_Library
	@sudo mkdir -p ${WORK_D}/Library/StartupItems
	@sudo chown root:wheel ${WORK_D}/Library/StartupItems
	@sudo chmod 755 ${WORK_D}/Library/StartupItems

l_System: l_root
	@sudo mkdir -p ${WORK_D}/System
	@sudo chown -R root:wheel ${WORK_D}/System
	@sudo chmod -R 755 ${WORK_D}/System

l_System_Library: l_System
	@sudo mkdir -p ${WORK_D}/System/Library
	@sudo chown -R root:wheel ${WORK_D}/System/Library
	@sudo chmod -R 755 ${WORK_D}/System/Library

l_System_Library_Extensions: l_System_Library
	@sudo mkdir -p ${WORK_D}/System/Library/Extensions
	@sudo chown -R root:wheel ${WORK_D}/System/Library/Extensions
	@sudo chmod -R 755 ${WORK_D}/System/Library/Extensions

l_System_Library_User_Template: l_System_Library
	@sudo mkdir -p ${WORK_D}/System/Library/User\ Template/English.lproj
	@sudo chown -R root:wheel ${WORK_D}/System/Library/User\ Template/English.lproj
	@sudo chmod 700 ${WORK_D}/System/Library/User\ Template
	@sudo chmod -R 755 ${WORK_D}/System/Library/User\ Template/English.lproj

l_System_Library_User_Template_Library: l_System_Library_User_Template
	@sudo mkdir -p ${WORK_D}/System/Library/User\ Template/English.lproj/Library
	@sudo chown root:wheel ${WORK_D}/System/Library/User\ Template/English.lproj/Library
	@sudo chmod 700 ${WORK_D}/System/Library/User\ Template/English.lproj/Library

l_System_Library_User_Template_Pictures: l_System_Library_User_Template
	@sudo mkdir -p ${WORK_D}/System/Library/User\ Template/English.lproj/Pictures
	@sudo chown root:wheel ${WORK_D}/System/Library/User\ Template/English.lproj/Pictures
	@sudo chmod 700 ${WORK_D}/System/Library/User\ Template/English.lproj/Pictures

l_System_Library_User_Template_Preferences: l_System_Library_User_Template_Library
	@sudo mkdir -p ${USER_TEMPLATE_PREFERENCES}
	@sudo chown root:wheel ${USER_TEMPLATE_PREFERENCES}
	@sudo chmod -R 700 ${USER_TEMPLATE_PREFERENCES}

l_System_Library_User_Template_Application_Support: l_System_Library_User_Template_Library
	@sudo mkdir -p ${USER_TEMPLATE_APPLICATION_SUPPORT}
	@sudo chown root:wheel ${USER_TEMPLATE_APPLICATION_SUPPORT}
	@sudo chmod -R 700 ${USER_TEMPLATE_APPLICATION_SUPPORT}

# These user domain locations are for use in rare circumstances, and
# as a last resort only for repackaging applications that use them.
# A notice will be issued during the build process.
l_Users: l_root
	@sudo mkdir -p ${WORK_D}/Users
	@sudo chown root:admin ${WORK_D}/Users
	@sudo chmod 755 ${WORK_D}/Users
	@echo "Creating \"Users\" directory"
	
l_Users_Shared: l_Users
	@sudo mkdir -p ${WORK_D}/Users/Shared
	@sudo chown root:wheel ${WORK_D}/Users/Shared
	@sudo chmod 1777 ${WORK_D}/Users/Shared
	@echo "Creating \"Users/Shared\" directory"

# file packaging rules

pack-directory-service-preference-%: % l_Library_Preferences_DirectoryService
	sudo install -m 600 -o root -g admin $< ${WORK_D}/Library/Preferences/DirectoryService

pack-site-python-%: % l_Library_Python_26_site_packages
	@sudo ${INSTALL} -m 644 -g admin -o root $< ${WORK_D}/Library/Python/2.6/site-packages

pack-siteruby-%: % l_Library_Ruby_Site_1_8
	@sudo ${INSTALL} -m 644 -g wheel -o root $< ${WORK_D}/Library/Ruby/Site/1.8

pack-Library-Fonts-%: % l_Library_Fonts
	@sudo ${INSTALL} -m 664 -g admin -o root $< ${WORK_D}/Library/Fonts

pack-Library-LaunchAgents-%: % l_Library_LaunchAgents
	@sudo ${INSTALL} -m 644 -g wheel -o root $< ${WORK_D}/Library/LaunchAgents

pack-Library-LaunchDaemons-%: % l_Library_LaunchDaemons
	@sudo ${INSTALL} -m 644 -g wheel -o root $< ${WORK_D}/Library/LaunchDaemons

pack-Library-QuickTime-%: % l_Library_QuickTime
	@sudo ${CP} -R $< ${WORK_D}/Library/QuickTime
	@sudo chown -R root:wheel ${WORK_D}/Library/QuickTime/$<
	@sudo chmod -R 755 ${WORK_D}/Library/QuickTime/$<

pack-Library-PreferencePanes-%: % l_Library_PreferencePanes
	@sudo ${CP} -R $< ${WORK_D}/Library/PreferencePanes
	@sudo chown -R root:wheel ${WORK_D}/Library/PreferencePanes/$<
	@sudo chmod -R 755 ${WORK_D}/Library/PreferencePanes/$<

pack-Library-Preferences-%: % l_Library_Preferences
	@sudo ${INSTALL} -m 644 -g admin -o root $< ${WORK_D}/Library/Preferences

pack-ppd-%: % l_PPDs
	@sudo ${INSTALL} -m 664 -g admin -o root $< ${WORK_D}/Library/Printers/PPDs/Contents/Resources

pack-script-%: % scriptdir
	@sudo ${INSTALL} -m 755 $< ${SCRIPT_D}

pack-resource-%: % resourcedir
	@sudo ${INSTALL} -m 755 $< ${RESOURCE_D}

pack-user-template-plist-%: % l_System_Library_User_Template_Preferences
	@sudo ${INSTALL} -m 644 $< ${USER_TEMPLATE_PREFERENCES}

pack-user-picture-%: % l_Library_Desktop_Pictures
	@sudo ${INSTALL} -m 644 $< ${WORK_D}/Library/Desktop\ Pictures

# posixy file stanzas

pack-etc-%: % l_private_etc
	@sudo ${INSTALL} -m 644 -g wheel -o root $< ${WORK_D}/private/etc

pack-usr-bin-%: % l_usr_bin
	@sudo ${INSTALL} -m 755 -g wheel -o root $< ${WORK_D}/usr/bin

pack-usr-sbin-%: % l_usr_sbin
	@sudo ${INSTALL} -m 755 -g wheel -o root $< ${WORK_D}/usr/sbin

pack-usr-local-bin-%: % l_usr_local_bin
	@sudo ${INSTALL} -m 755 -g wheel -o root $< ${WORK_D}/usr/local/bin

pack-usr-local-sbin-%: % l_usr_local_sbin
	@sudo ${INSTALL} -m 755 -g wheel -o root $< ${WORK_D}/usr/local/sbin

pack-var-root-Library-Preferences-%: % l_var_root_Library_Preferences
	@sudo ${INSTALL} -m 600 -g wheel -o root $< ${WORK_D}/private/var/root/Library/Preferences

pack-man-%: l_usr_man
	@sudo ${INSTALL} -m 0644 -g wheel -o root $< ${WORK_D}/usr/share/man

pack-man1-%: l_usr_man_man1
	@sudo ${INSTALL} -m 0644 -g wheel -o root $< ${WORK_D}/usr/share/man/man1

pack-man2-%: l_usr_man_man2
	@sudo ${INSTALL} -m 0644 -g wheel -o root $< ${WORK_D}/usr/share/man/man2

pack-man3-%: l_usr_man_man3
	@sudo ${INSTALL} -m 0644 -g wheel -o root $< ${WORK_D}/usr/share/man/man3

pack-man4-%: l_usr_man_man4
	@sudo ${INSTALL} -m 0644 -g wheel -o root $< ${WORK_D}/usr/share/man/man4

pack-man5-%: l_usr_man_man5
	@sudo ${INSTALL} -m 0644 -g wheel -o root $< ${WORK_D}/usr/share/man/man5

pack-man6-%: l_usr_man_man6
	@sudo ${INSTALL} -m 0644 -g wheel -o root $< ${WORK_D}/usr/share/man/man6

pack-man7-%: l_usr_man_man7
	@sudo ${INSTALL} -m 0644 -g wheel -o root $< ${WORK_D}/usr/share/man/man7

pack-man8-%: l_usr_man_man8
	@sudo ${INSTALL} -m 0644 -g wheel -o root $< ${WORK_D}/usr/share/man/man8

pack-hookscript-%: % l_etc_hooks
	@sudo ${INSTALL} -m 755 $< ${WORK_D}/private/etc/hooks

# Applications and Utilities
#
# We use ${TAR} because it respects resource forks. This is still
# critical - just when I thought I'd seen the last of the damn things, Apple
# decided to stash compressed binaries in them in 10.6.

unbz2-applications-%: %.tar.bz2 l_Applications
	@sudo ${TAR} xjf $< -C ${WORK_D}/Applications
	@sudo chown -R root:admin ${WORK_D}/Applications/$(shell echo $< | sed s/\.tar\.bz2//g)

unbz2-utilities-%: %.tar.bz2 l_Applications_Utilities
	@sudo ${TAR} xjf $< -C ${WORK_D}/Applications/Utilities
	@sudo chown -R root:admin ${WORK_D}/Applications/Utilities/$(shell echo $< | sed s/\.tar\.bz2//g)

ungz-applications-%: %.tar.gz l_Applications
	@sudo ${TAR} xzf $< -C ${WORK_D}/Applications
	@sudo chown -R root:admin ${WORK_D}/Applications/$(shell echo $< | sed s/\.tar\.gz//g)

ungz-utilities-%: %.tar.gz l_Applications_Utilities
	@sudo ${TAR} xzf $< -C ${WORK_D}/Applications/Utilities
	@sudo chown -R root:admin ${WORK_D}/Applications/Utilities/$(shell echo $< | sed s/\.tar\.gz//g)

# ${DITTO} preserves resource forks by default
# --noqtn drops quarantine information
# -k -x extracts zip
# Zipped applications commonly found on the Web usually have the suffixes substituted, so these stanzas substitute them back

unzip-applications-%: %.zip l_Applications
	@sudo ${DITTO} --noqtn -k -x $< ${WORK_D}/Applications/
	@sudo chown -R root:admin ${WORK_D}/Applications/$(shell echo $< | sed s/\.zip/.app/g)

unzip-utilities-%: %.zip l_Applications_Utilities
	@sudo ${DITTO} --noqtn -k -x $< ${WORK_D}/Applications/Utilities/
	@sudo chown -R root:admin ${WORK_D}/Applications/Utilities/$(shell echo $< | sed s/\.zip/.app/g)
