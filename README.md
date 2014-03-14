puppet-useradd-localfiles
=========================

Puppet useradd provider (User) that checks and updates only /etc/passwd. This
is primarily useful to purge /etc/passwd while using ldap for passwd entries in
nsswitch.conf

The master branch is dedicated to the 3.x puppet release (tested on 3.4).

To use this provider, put the useradd.rb file into a module directory such as:

MYMODULE/lib/puppet/provider/user/

You must have pluginsync enabled on your puppetmaster for the provider to be
deployed correctly.
