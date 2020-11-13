## A Box for Network Tests

### Prerequisites

* Install [VirtualBox](https://www.virtualbox.org/)
* Install [Vagrant](https://www.vagrantup.com/)
* Install [direnv](https://www.direnv.net)

This folder contains a `Vagrantfile` and some supporting files that allow to setup a virtual box for working / experimenting. The box is based on Ubuntu/Focal.

### Configuration

The virtual box is configured by the following environment variables:

* `VAGRANT_BOX_BRIDGE_INTERFACE`
* `VAGRANT_BOX_STATIC_IP`

These environment variables can be configured using `direnv`. Copy the file `.envrc.example` into `.envrc` and adjust its contents.
