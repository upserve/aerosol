class SluggerDeploys::Deploy
  include Dockly::Util::DSL
  include Dockly::Util::Logger::Mixin

  logger_prefix '[slugger deploy]'
  dsl_attribute :stop_command, :db_config_path,
                :instance_live_grace_period, :app_port,
                :continue_if_stop_app_fails, :stop_app_retries,
                :sleep_before_termination, :post_deploy_command

  dsl_class_attribute :ssh, SluggerDeploys::Connection
  dsl_class_attribute :migration_ssh, SluggerDeploys::Connection
  dsl_class_attribute :local_ssh, SluggerDeploys::Connection
  dsl_class_attribute :auto_scaling, SluggerDeploys::AutoScaling

  default_value :db_config_path, 'config/database.yml'
  default_value :instance_live_grace_period, 30 * 60 # 30 Minutes
  default_value :continue_if_stop_app_fails, false
  default_value :stop_app_retries, 2
  default_value :sleep_before_termination, 20

  def live_check(arg = nil)
    case
    when arg.nil?
      @live_check
    when arg.start_with?('/')
      @live_check = arg
    else
      @live_check = "/#{arg}"
    end
    @live_check
  end

  def do_not_migrate!
    self.instance_variable_set(:@db_config_path, nil)
  end

  def migration(opts = {})
    self.db_config_path(opts[:db_config_path])
  end

  def migrate?
    !!db_config_path
  end

  def local_ssh_ref
    local_ssh || ssh
  end

  def run_post_deploy
    return if post_deploy_command.nil?
    info "running post deploy: #{post_deploy_command}"
    if system(post_deploy_command)
      info "post deploy ran successfully"
      true
    else
      raise "post deploy failed"
    end
  end

  class << self
    def find(&block)
      inst = instances.find(&block)
      inst[1] unless inst.nil?
    end

    def method_missing(name, *args)
      if name =~ /\Afind_by_(?<dsl>.*)\z/
        dsl = Regexp.last_match[:dsl].to_sym
        if (args.length == 1) && [:ssh, :migration_ssh, :package, :auto_scaling].include?(dsl)
          if inst = instances.find { |k, v| v.public_send(dsl).name == args[0] rescue nil }
            inst[1]
          end
        else
          super
        end
      else
        super
      end
    end
  end

  def generate_ssh_command(instance)
    ssh_command = "ssh -o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' "
    unless local_ssh_ref.nil?
      unless local_ssh_ref.jump.nil? || local_ssh_ref.jump.empty?
        ssh_command << "-o 'ProxyCommand=ssh -W %h:%p "
        ssh_command << "#{local_ssh_ref.jump[:user]}@" if local_ssh_ref.jump[:user]
        ssh_command << "#{local_ssh_ref.jump[:host]}' "
      end
      ssh_command << "#{local_ssh_ref.user}@" unless local_ssh_ref.user.nil?
    end
    ssh_command << "#{instance.public_hostname}"
  end

  def generate_ssh_commands
    group = SluggerDeploys::AutoScaling.latest_for_tag('Deploy', name.to_s)
    raise "Could not find any auto scaling groups for this deploy (#{name})." if group.nil?

    ssh_commands = []

    with_prefix("[#{name}]") do |logger|
      logger.info "found group: #{group.name}"
      instances = group.all_instances
      raise "Could not find any instances for auto scaling group #{group.name}" if instances.empty?
      instances.each do |instance|
        logger.info "printing ssh command for #{instance.public_hostname}"
        ssh_commands << generate_ssh_command(instance)
      end
    end

    return ssh_commands
  end
end
