class Aerosol::LaunchConfiguration
  include Aerosol::AWSModel
  include Dockly::Util::Logger::Mixin

  logger_prefix '[aerosol launch_configuration]'
  aws_attribute :launch_configuration_name, :image_id, :instance_type, :security_groups, :user_data,
                :iam_instance_profile, :kernel_id, :key_name, :spot_price, :created_time,
                :associate_public_ip_address

  primary_key :launch_configuration_name
  default_value(:security_groups) { [] }

  def launch_configuration_name(arg = nil)
    if arg
      raise "You cannot set the launch_configuration_name directly" unless from_aws
      @launch_configuration_name = arg
    else
      @launch_configuration_name || default_identifier
    end
  end

  def ami(name=nil)
    warn 'Warning: Use `image_id` instead `ami` for a launch configuration'
    image_id(name)
  end

  def iam_role(name=nil)
    warn 'Warning: Use `iam_instance_profile` instead `iam_role` for a launch configuration'
    iam_instance_profile(name)
  end

  def security_group(group)
    security_groups << group
  end

  def create!
    ensure_present! :image_id, :instance_type

    info self.to_s
    conn.create_launch_configuration({
      image_id: image_id,
      instance_type: instance_type,
      launch_configuration_name: launch_configuration_name,
    }.merge(create_options))
    sleep 10 # TODO: switch to fog models and .wait_for { ready? }
  end

  def destroy!
    info self.to_s
    conn.delete_launch_configuration(launch_configuration_name: launch_configuration_name)
  end

  def all_instances
    Aerosol::Instance.all.select { |instance|
      !instance.launch_configuration.nil? &&
        (instance.launch_configuration.launch_configuration_name == launch_configuration_name)
    }.each(&:description)
  end

  def self.request_all_for_token(next_token)
    options = next_token.nil? ? {} : { next_token: next_token }
    Aerosol::AWS.auto_scaling.describe_launch_configurations(options)
  end

  def self.request_all
    next_token = nil
    lcs = []

    begin
      new_lcs = request_all_for_token(next_token)
      lcs.concat(new_lcs.launch_configurations)
      next_token = new_lcs.next_token
    end until next_token.nil?

    lcs
  end

  def to_s
    %{Aerosol::LaunchConfiguration { \
"launch_configuration_name" => "#{launch_configuration_name}", \
"image_id" => "#{image_id}", \
"instance_type" => "#{instance_type}", \
"security_groups" => #{security_groups.to_s}, \
"user_data" => "#{user_data}", \
"iam_instance_profile" => "#{iam_instance_profile}", \
"kernel_id" => "#{kernel_id}", \
"key_name" => "#{key_name}", \
"spot_price" => "#{spot_price}", \
"created_time" => "#{created_time}" \
}}
  end

private
  def create_options
    { # TODO Add dsl so that 'BlockDeviceMappings' may be specified
      iam_instance_profile: iam_instance_profile,
      kernel_id: kernel_id,
      key_name: key_name,
      security_groups: security_groups,
      spot_price: spot_price,
      user_data: Aerosol::Util.strip_heredoc(user_data || ''),
      associate_public_ip_address: associate_public_ip_address
    }.reject { |k, v| v.nil? }
  end

  def conn
    Aerosol::AWS.auto_scaling
  end
end
