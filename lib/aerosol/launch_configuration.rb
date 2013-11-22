class Aerosol::LaunchConfiguration
  include Aerosol::AWSModel
  include Dockly::Util::Logger::Mixin

  logger_prefix '[aerosol launch_configuration]'
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
      @aws_identifier || "#{name}-#{Aerosol::Util.git_sha}"
    end
  end

  def security_group(group)
    security_groups << group
  end

  def create!
    ensure_present! :ami, :instance_type

    info self.to_s
    conn.create_launch_configuration(ami, instance_type, aws_identifier, create_options)
    sleep 10 # TODO: switch to fog models and .wait_for { ready? }
  end

  def destroy!
    info self.to_s
    conn.delete_launch_configuration(aws_identifier)
  end

  def all_instances
    Aerosol::Instance.all.select { |instance|
      !instance.launch_configuration.nil? &&
        (instance.launch_configuration.aws_identifier == self.aws_identifier)
    }.each(&:description)
  end

  def self.request_all
    Aerosol::AWS.auto_scaling
                .describe_launch_configurations
                .body
                .[]('DescribeLaunchConfigurationsResult')
                .[]('LaunchConfigurations')
  end

  def to_s
    %{Aerosol::LaunchConfiguration { \
"aws_identifier" => "#{aws_identifier}", \
"ami" => "#{ami}", \
"instance_type" => "#{instance_type}", \
"security_groups" => #{security_groups.to_s}, \
"user_data" => "#{user_data}", \
"iam_role" => "#{iam_role}", \
"kernel_id" => "#{kernel_id}", \
"key_name" => "#{key_name}", \
"spot_price" => "#{spot_price}", \
"created_time" => "#{created_time}" \
}}
  end

private
  def create_options
    { # TODO Add dsl so that 'BlockDeviceMappings' may be specified
      'IamInstanceProfile' => iam_role,
      'KernelId' => kernel_id,
      'KeyName' => key_name,
      'SecurityGroups' => security_groups,
      'SpotPrice' => spot_price,
      'UserData' => Aerosol::Util.strip_heredoc(user_data || '')
    }.reject { |k, v| v.nil? }
  end

  def conn
    Aerosol::AWS.auto_scaling
  end
end
