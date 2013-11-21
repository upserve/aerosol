Aerosol
=======

Aerosol is a gem made to ease the pain of deploying. For this gem to be useful, quite a few assumptions are made about your stack:

- You are using `ActiveRecord` if you're deploying a Rails repo
- You use AWS

Although only a specific type of repository may be used, these assumptions allow us to define a simple DSL to describe your repository.

The DSL
-------

The DSL is broken down into multiple objects, all of which conform to a specific format. Each object starts with the name of the section,
followed by a name for the object you're creating, and a block for configuration.

```ruby
auto_scaling :test_auto_scaling do
  # code here
end
```

Each object has an enumeration of valid attributes. The following code sets the `max_size` attribute in a `auto_scaling` group called `test_auto_scaling`:

```ruby
auto_scaling :test_auto_scaling do
  max_size 1
end
```

Finally, each object has zero or more valid references to other DSL objects. The following code sets `auto_scaling` that references a `launch_configuration`:

```ruby
launch_configuration :my_launch_config do
  max_size 1
end

auto_scaling :my_auto_scaling do
  launch_configuration :my_launch_config
end
```

Below is an alternative syntax that accomplishes the same thing:

```ruby
auto_scaling :my_auto_scaling do
  launch_configuration do
    max_size 1
  end
end
```

`ssh`
-----

The `ssh` DSL is used to define ssh connections used throughout the deploy. Currently, there are three uses for this: local sessions, migrations and live checks. It has the following attributes:

  dsl_attribute :user, :host, :jump

- `user`
    - required: `true`
    - default: `nil`
    - description: the user to ssh in as
- `host`
    - required: `true`
    - default: `nil`
    - description: the host of the server to ssh into
- `jump`
    - required: `false`
    - default: `nil`
    - description: an optional jump server's configuration; should be given as a hash with the keys `:host` and `:user`

`launch_configuration`
----------------------

The `launch_configuration` DSL is used to define AWS launch configurations. It has the following attributes:

- `ami`
    - required: `true`
    - default: `nil`
    - description: the AWS AMI to use on instances using this configuration
- `instance_type`
    - required: `true`
    - default: `nil`
    - description: the type of AWS instance that will be using this configuration (m1.large, etc.)
- `security_groups`:
    - required: `false`
    - default: `[]`
    - description: an optional list of security groups to add the configured instances to
- `user_data`
    - required: `false`
    - default: `nil`
    - description: startup scripts for new instances
- `iam_role`
    - required: `false`
    - default: `nil`
    - description: the IAM role of instances using this configuration
- `kernel_id`
    - required: `false`
    - default: `nil`
    - description: the id of the kernel associated with the ami
- `key_name`
    - required: `false`
    - default: `nil`
    - description: the name of the ec2 key pair
- `spot_price`
    - required: `false`
    - default: `nil`
    - description: the max hourly price to be paid for any spot prices

`auto_scaling`
--------------

The `auto_scaling` DSL is used to define AWS auto scaling groups. It has the following attributes:

- `availability_zones`
    - required: `true`
    - default: `nil`
    - description: a list of availability zones for the auto scaling group
- `min_size`, `max_size`
    - required: `true`
    - default: `nil`
    - description: the min and max sizes of the auto scaling group
- `default_cooldown`
    - required: `false`
    - default: `nil`
    - description: the number of seconds after a scaling activity completes before any further trigger-related scaling activities can start
- `desired_capacity`
    - required: `false`
    - default: `nil`
    - description: the number instances that should be running in the group
- `health_check_grace_period`
    - required: `false`
    - default: `nil`
    - description: the number seconds aws waits before it performs a health check
- `health_check_type`
    - required: `false`
    - default: `nil`
    - description: the type of health check to perform, `'ELB'` and `'EC2'` are valid options
- `load_balancer_names`
    - required: `false`
    - default: `nil`
    - description: a list of the names of desired load balancers
- `placement_group`
    - required: `false`
    - default: `nil`
    - description: a list of the names of desired load balancers
- `tag`
    - required: `false`
    - default: `{}`
    - description: a hash of tags for the instances in the group

In addition to those attributes, `auto_scaling` also has a required reference to `launch_configuration`.

`deploy`
--------

The `deploy` DSL ties together all of the other DSLs, allowing you to deploy your app. It has the following attributes:

- `stop_command`
    - required: `true`
    - default: nil
    - description: the command to run on an instance to stop the app
- `db_config_path`
    - required: `true`
    - default: `config/database.yml`
    - description: the relative path of your database config file
- `instance_live_grace_period`
    - required: `true`
    - default: `36000` (10 minutes)
    - description: the number of seconds to wait for an instance to be live
- `app_port`
    - required: `true`
    - default: `nil`
    - description: the port that your app runs on
- `stop_app_retries`
    - required: `true`
    - default: `2`
    - description: the number of times to retry stopping the app
- `continue_if_stop_app_fails`
    - required: `false`
    - default: `nil`
    - description: when `true`, will ignore a failure of the stop app step

It has the following references:

- `ssh`
    - required: `true`
    - default: `nil`
    - class: Aerosol::Connection
    - description: configuration to ssh into your new instances
- `migration_ssh`
    - required: `false`
    - default: `nil`
    - class: Aerosol::Connection
    - description: configuration to ssh into to run a migration
- `local_ssh`
    - required: `false`
    - default: `nil`
    - class: Aerosol::Connection
    - description: configuration to ssh into from your local machine (generates ssh command for you)
- `package`
    - required: `true`
    - default: `nil`
    - class: Aerosol::Deb
    - description: the deb package associated with this deploy
- `auto_scaling`
    - required: `true`
    - default: `nil`
    - class: Aerosol::AutoScaling
    - description: the auto scaling config associated with this deploy


Demo
===

```ruby
launch_configuration :aerosol_launchconfig do
  instance_type 'm1.large'
  ami 'ami-number'
  iam_role 'role-app'
  key_name 'app'
  security_groups ['app']

  user_data ERB.new(File.read('startup.sh.erb')).result(binding)
  # Does not need to be erb, but works really well when it is!
end

auto_scaling :aerosol_autoscaling do
  availability_zones ['us-east-1a']
  max_size 1
  min_size 1
  launch_configuration :aerosol_launchconfig
  tag 'Name' => 'app'
  tag 'dtdg-group' => 'app'
end

ssh :aerosol_ssh do
  user 'ubuntu'
end

ssh :aerosol_migration do
  user 'ubuntu'
  host 'database-instance'
end

ssh :aerosol_local do
  jump :user => 'ubuntu', :host => 'jumpserver.example.com'
end

deploy :aerosol_deploy do
  package :aerosol_package
  ssh :aerosol_ssh
  migration_ssh :aerosol_migration
  local_ssh :aerosol_local
  auto_scaling :aerosol_autoscaling
  stop_command 'sudo stop app'
  live_check '/version'
  app_port 443
  post_deploy_command 'bundle exec rake postdeploycommand'
end
```

Copyright (c) 2013 Swipely, Inc. See LICENSE.txt for further details.
