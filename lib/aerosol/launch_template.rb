class Aerosol::LaunchTemplate
  include Aerosol::AWSModel
  include Dockly::Util::Logger::Mixin

  logger_prefix '[aerosol launch_template]'
  aws_attribute :launch_template_name, :launch_template_id, :latest_version_number,
                :image_id, :instance_type, :security_groups, :user_data,
                :iam_instance_profile, :kernel_id, :key_name, :spot_price, :created_time,
                :network_interfaces, :block_device_mappings, :ebs_optimized
  dsl_attribute :meta_data

  primary_key :launch_template_name
  default_value(:security_groups) { [] }
  default_value(:meta_data) { {} }

  def launch_template_name(arg = nil)
    if arg
      raise "You cannot set the launch_template_name directly" unless from_aws
      @launch_template_name = arg
    else
      @launch_template_name || default_identifier
    end
  end

  def security_group(group)
    security_groups << group
  end

  def create!
    ensure_present! :image_id, :instance_type

    info "creating launch template"
    conn.create_launch_template(
      launch_template_name: launch_template_name,
      launch_template_data: {
        image_id: image_id,
        instance_type: instance_type,
        monitoring: {
          enabled: true
        },
      }.merge(create_options)
    )

    info self.inspect
  end

  def destroy!
    info self.to_s
    raise StandardError.new('No launch_template_name found') unless launch_template_name
    conn.delete_launch_template(launch_template_name: launch_template_name)
  end

  def all_instances
    Aerosol::Instance.all.select { |instance|
      !instance.launch_template.nil? &&
        (instance.launch_template.launch_template_name == launch_template_name)
    }.each(&:description)
  end

  def self.request_all_for_token(next_token)
    options = next_token.nil? ? {} : { next_token: next_token }
    Aerosol::AWS.compute.describe_launch_templates(options)
  end

  def self.request_all
    next_token = nil
    lts = []

    begin
      new_lts = request_all_for_token(next_token)
      lts.concat(new_lts.launch_templates)
      next_token = new_lts.next_token
    end until next_token.nil?
    lts
  end

  def to_s
    %{Aerosol::LaunchTemplate { \
"launch_template_name" => "#{launch_template_name}", \
"launch_template_id" => "#{launch_template_id}", \
"latest_version_number" => "#{latest_version_number}", \
"image_id" => "#{image_id}", \
"instance_type" => "#{instance_type}", \
"security_group_ids" => #{security_groups.to_s}, \
"user_data" => "#{user_data}", \
"iam_instance_profile" => "#{iam_instance_profile}", \
"kernel_id" => "#{kernel_id}", \
"key_name" => "#{key_name}", \
"spot_price" => "#{spot_price}", \
"created_time" => "#{created_time}", \
"block_device_mappings" => #{block_device_mappings}", \
"ebs_optimized" => #{ebs_optimized} \
}}
  end

  def corrected_user_data
    realized_user_data = user_data.is_a?(Proc) ? user_data.call : user_data

    Base64.encode64(Aerosol::Util.strip_heredoc(realized_user_data || ''))
  end

private
  def create_options
    instance_market_options = {
      market_type: 'spot',
      spot_options: {
        max_price: spot_price
      }
    } if spot_price

    {
      iam_instance_profile: { name: iam_instance_profile },
      kernel_id: kernel_id,
      key_name: key_name,
      security_group_ids: security_groups,
      instance_market_options: instance_market_options,
      user_data: corrected_user_data,
      network_interfaces: network_interfaces,
      block_device_mappings: block_device_mappings,
      ebs_optimized: ebs_optimized,
    }.reject { |k, v| v.nil? }
  end

  def conn
    Aerosol::AWS.compute
  end
end
