class Aerosol::Deploy
  include Dockly::Util::DSL
  include Dockly::Util::Logger::Mixin

  logger_prefix '[aerosol deploy]'
  dsl_attribute :stop_command, :db_config_path,
                :instance_live_grace_period, :app_port,
                :continue_if_stop_app_fails, :stop_app_retries,
                :sleep_before_termination, :post_deploy_command,
                :ssl, :log_files, :tail_logs, :assume_role

  dsl_class_attribute :ssh, Aerosol::Connection
  dsl_class_attribute :migration_ssh, Aerosol::Connection
  dsl_class_attribute :local_ssh, Aerosol::Connection
  dsl_class_attribute :auto_scaling, Aerosol::AutoScaling

  default_value :db_config_path, 'config/database.yml'
  default_value :instance_live_grace_period, 30 * 60 # 30 Minutes
  default_value :continue_if_stop_app_fails, false
  default_value :stop_app_retries, 2
  default_value :sleep_before_termination, 20
  default_value :ssl, false
  default_value :tail_logs, false
  default_value :log_files, ['/var/log/syslog']
  default_value :assume_role, nil

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

  def is_alive?(&block)
    @is_alive = block unless block.nil?
    @is_alive
  end

  def live_check_url
    [ssl ? 'https' : 'http', '://localhost:', app_port, live_check].join
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

  def perform_role_assumption
    return if assume_role.nil?
    Aws.config.update(
      credentials: Aws::AssumeRoleCredentials.new(
        role_arn: assume_role, role_session_name: 'aerosol'
      )
    )
  end

  def sts
    Aerosol::AWS.sts
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
    ssh_command << "#{instance.public_hostname || instance.private_ip_address}"
  end

  def generate_ssh_commands
    group = Aerosol::AutoScaling.latest_for_tag('Deploy', auto_scaling.namespaced_name)
    raise "Could not find any auto scaling groups for this deploy (#{name})." if group.nil?

    ssh_commands = []

    with_prefix("[#{name}]") do |logger|
      logger.info "found group: #{group.auto_scaling_group_name}"
      instances = group.all_instances
      raise "Could not find any instances for auto scaling group #{group.namespaced_name}" if instances.empty?
      instances.each do |instance|
        logger.info "printing ssh command for #{instance.public_hostname  || instance.private_ip_address}"
        ssh_commands << generate_ssh_command(instance)
      end
    end

    return ssh_commands
  end
end
