#!/bin/bash
echo "### provision aliases and path"
# create symbolic links in the /home/vagrant for all files in the home
for a in `find /vagrant/home -name "*" -type f` ; do
  rm -f $VAGRANT_USER_HOME/`basename $a`
  ln -rs $a /home/vagrant
done
echo "export PATH=$PATH:/vagrant/bin" >> $VAGRANT_USER_HOME/.bashrc
# echo "source /vagrant/.envrc" >> $VAGRANT_USER_HOME/.bashrc

echo update locale
update-locale LANG=en_US.UTF-8
