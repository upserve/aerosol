require 'rubygems'
require 'slugger_deploys'
require 'clamp'

class SluggerDeploys::AbstractCommand < Clamp::Command
  option ['-f', '--file'], 'FILE', 'deploys file to read', :default => 'deploys.rb', :attribute_name => :file

  def execute
    if File.exist?(file)
      SluggerDeploys.load_file = file
    else
      raise 'Could not find a deploys file!'
    end
  end
end

class SluggerDeploys::SshCommand < SluggerDeploys::AbstractCommand
  option ['-r', '--run'], :flag, 'run first ssh command', :attribute_name => :run_first
  parameter 'DEPLOY', 'the deploy to list commands for', :attribute_name => :deploy_name

  def execute
    super
    if deploy = SluggerDeploys.deploy(deploy_name.to_sym)
      ssh_commands = deploy.generate_ssh_commands
      raise 'No instances to ssh too!' if ssh_commands.empty?

      ssh_commands.each do |ssh_command|
        puts ssh_command
      end

      if run_first?
        system(ssh_commands.first)
      end
    end
  end
end

class SluggerDeploys::AutoScalingCommand < SluggerDeploys::AbstractCommand
  parameter 'AUTOSCALING_GROUP', 'the auto scaling group to create', :attribute_name => :autoscaling_name

  def execute
    super
    if autoscaling = SluggerDeploys.auto_scaling(autoscaling_name.to_sym)
      autoscaling.create
    end
  end
end

class SluggerDeploys::Cli < SluggerDeploys::AbstractCommand
  subcommand ['ssh', 's'], 'Print ssh commands for latest running instances', SluggerDeploys::SshCommand
  subcommand ['autoscaling', 'as'], 'Create autoscaling group', SluggerDeploys::AutoScalingCommand
end

