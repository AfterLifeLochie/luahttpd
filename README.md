luahttpd
========

Greetings! In this bundle you'll find everything you need to setup the httpd. You will need to install Lua 5.1 with the lfs and luasocket modules, and configure the default paths in the top of 'server.lua'

   /http       : the effective ~/www/ directory of the server. Included are
                 a few test-cases for you to play with to demonstrate the
                 server features (and possibly bugs, erk!).

   /module     : The webserver module folder. In here are all the installed
                 (written!) modules.

   /templates  : The HTML templates used by the server. Does not need a
                 server restart for changes. Use %<VAR>% in templates to
                 get variable values (restricted!).

   /helper.lua : Some helper code.

   /server.lua : The main server code. Go here to edit your settings, top
                 of the file.

   /thread.lua : My insane threading manager (most of which isn't really
                 used in the server, presently).
