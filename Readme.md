A Nagios/Icinga plugin to check remote Nagios/Icinga installations.

This can be used in scenarios, where Icinga is part of the
environment. Then a "2nd level" Icinga can check, that all "1st level"
instances are fine.

# Installation

## As file

```
gem install excon
cp check_remote_icinga.rb /usr/lib/nagios/plugins
```

## As Debian package

1. package `excon` as Debian package (use https://github.com/jordansissel/fpm)
1. `dpkg-buildpackage -b`

# Want to improve this?

Send me your changes via pull-request.

# License

GPLv3. Let me know if you have other suggestions

# Author

Jens Braeuer