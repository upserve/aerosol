class SluggerDeploys::LaunchConfiguration
  include SluggerDeploys::AWSModel
  include Dockly::Util::Logger::Mixin

  logger_prefix '[slugger launch_configuration]'
  aws_attribute :aws_identifier  => 'LaunchConfigurationName',
                :ami             => 'ImageId',
                :instance_type   => 'InstanceType',
                :security_groups => 'SecurityGroups',
                :user_data       => 'UserData',
                :iam_role        => 'IamInstanceProfile',
                :kernel_id       => 'KernelId',
                :key_name        => 'KeyName',
                :spot_price      => 'SpotPrice',
                :created_time    => 'CreatedTime'

  primary_key :aws_identifier
  default_value(:security_groups) { [] }

  def aws_identifier(arg = nil)
    if arg
      raise "You cannot set the aws_identifer directly" unless from_aws
      @aws_identifier = arg
    else
      @aws_identifier || "#{name}-#{SluggerDeploys::Util.git_sha}"
    end
  end

  def security_group(group)
    security_groups << group
  end

  def create!
    ensure_present! :ami, :instance_type

    info self.inspect
    conn.create_launch_configuration(ami, instance_type, aws_identifier, create_options)
    sleep 10 # TODO: switch to fog models and .wait_for { ready? }
  end

  def destroy!
    info self.inspect
    conn.delete_launch_configuration(aws_identifier)
  end

  def all_instances
    SluggerDeploys::Instance.all.select { |instance|
      !instance.launch_configuration.nil? &&
        (instance.launch_configuration.aws_identifier == self.aws_identifier)
    }.each(&:description)
  end

  def self.request_all
    SluggerDeploys::AWS.auto_scaling
                .describe_launch_configurations
                .body
                .[]('DescribeLaunchConfigurationsResult')
                .[]('LaunchConfigurations')
  end

private
  def create_options
    { # TODO Add dsl so that 'BlockDeviceMappings' may be specified
      'IamInstanceProfile' => iam_role,
      'KernelId' => kernel_id,
      'KeyName' => key_name,
      'SecurityGroups' => security_groups,
      'SpotPrice' => spot_price,
      'UserData' => SluggerDeploys::Util.strip_heredoc(user_data || '')
    }.reject { |k, v| v.nil? }
  end

  def conn
    SluggerDeploys::AWS.auto_scaling
  end
end
