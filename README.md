puppet-useradd-localfiles
=========================

Puppet useradd provider (User) that checks and updates only /etc/passwd. This
is primarily useful to purge /etc/passwd while using ldap for passwd entries in
nsswitch.conf

The puppet2.x branch is dedicated to the 2.x puppet release (tested on 2.6 and 2.7).

To use this provider, put the useradd.rb file into a module directory such as:

MYMODULE/lib/puppet/provider/user/

You must have pluginsync enabled on your puppetmaster for the provider to be
deployed correctly.
