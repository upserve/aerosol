require 'rubygems'
require 'aerosol'
require 'clamp'

class Aerosol::AbstractCommand < Clamp::Command
  option ['-f', '--file'], 'FILE', 'aerosol file to read', :default => 'aerosol.rb', :attribute_name => :file

  def execute
    if File.exist?(file)
      Aerosol.load_file = file
    else
      raise 'Could not find an aerosol file!'
    end
  end
end

class Aerosol::SshCommand < Aerosol::AbstractCommand
  option ['-r', '--run'], :flag, 'run first ssh command', :attribute_name => :run_first
  parameter 'DEPLOY', 'the deploy to list commands for', :attribute_name => :deploy_name

  def execute
    super
    if deploy = Aerosol.deploy(deploy_name.to_sym)
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

class Aerosol::Cli < Aerosol::AbstractCommand
  subcommand ['ssh', 's'], 'Print ssh commands for latest running instances', Aerosol::SshCommand
end

