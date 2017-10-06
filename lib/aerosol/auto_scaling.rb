class Aerosol::AutoScaling
  include Aerosol::AWSModel
  include Dockly::Util::Logger::Mixin

  logger_prefix '[aerosol auto_scaling]'
  aws_attribute :auto_scaling_group_name, :availability_zones, :min_size, :max_size, :default_cooldown,
                :desired_capacity, :health_check_grace_period, :health_check_type, :load_balancer_names,
                :placement_group, :tags, :created_time, :vpc_zone_identifier, :target_group_arns
  aws_class_attribute :launch_configuration, Aerosol::LaunchConfiguration
  primary_key :auto_scaling_group_name

  def initialize(options={}, &block)
    tag = options.delete(:tag)
    super(options, &block)

    tags.merge!(tag) unless tag.nil?

    tags["GitSha"] ||= Aerosol::Util.git_sha
    tags["Deploy"] ||= namespaced_name
  end

  def auto_scaling_group_name(arg = nil)
    if arg
      raise "You cannot set the auto_scaling_group_name directly" unless from_aws
      @auto_scaling_group_name = arg
    else
      @auto_scaling_group_name || default_identifier
    end
  end

  def exists?
    info "auto_scaling: needed?: #{namespaced_name}: " +
         "checking for auto scaling group: #{auto_scaling_group_name}"
    exists = super
    info "auto scaling: needed?: #{namespaced_name}: " +
         "#{exists ? 'found' : 'did not find'} auto scaling group: #{auto_scaling_group_name}"
    exists
  end

  def create!
    ensure_present! :launch_configuration, :max_size, :min_size
    raise 'availability_zones or vpc_zone_identifier must be set' if [availability_zones, vpc_zone_identifier].none?

    info "creating auto scaling group"
    launch_configuration.create
    info self.inspect

    conn.create_auto_scaling_group({
      auto_scaling_group_name: auto_scaling_group_name,
      availability_zones: [*availability_zones],
      launch_configuration_name: launch_configuration.launch_configuration_name,
      max_size: max_size,
      min_size: min_size
    }.merge(create_options))
    sleep 10
  end

  def destroy!
    info self.inspect
    conn.delete_auto_scaling_group(auto_scaling_group_name: auto_scaling_group_name, force_delete: true)
    begin
      (0..2).each { break if deleting?; sleep 1 }
      launch_configuration.destroy
    rescue => ex
      info "Launch Config: #{launch_configuration} for #{auto_scaling_group_name} was not deleted."
      info ex.message
    end
  end

  def deleting?
    asgs = conn.describe_auto_scaling_groups(auto_scaling_group_names: [auto_scaling_group_name]).auto_scaling_groups

    return true if asgs.empty?

    asgs.first.status.to_s.include?('Delete')
  end

  def all_instances
    conn.describe_auto_scaling_groups(auto_scaling_group_names: [*auto_scaling_group_name])
        .auto_scaling_groups.first
        .instances.map { |instance| Aerosol::Instance.from_hash(instance) }
  end

  def tag(val)
    tags.merge!(val)
  end

  def tags(ary=nil)
    if !ary.nil?
      if ary.is_a? Hash
        ary.each do |key, value|
          tag key => value
        end
      else
        ary.each do |struct|
          tag struct[:key] => struct[:value]
        end
      end
    else
      @tags ||= {}
    end
  end

  def self.request_all_for_token(next_token)
    options = next_token.nil? ? {} : { next_token: next_token }
    Aerosol::AWS.auto_scaling.describe_auto_scaling_groups(options)
  end

  def self.request_all
    next_token = nil
    asgs = []

    begin
      new_asgs = request_all_for_token(next_token)
      asgs.concat(new_asgs.auto_scaling_groups)
      next_token = new_asgs.next_token
    end until next_token.nil?

    asgs
  end

  def self.latest_for_tag(key, value)
    all.select  { |group| group.tags[key] == value }
       .sort_by { |group| group.created_time }.last
  end

  def to_s
    %{Aerosol::AutoScaling { \
"auto_scaling_group_name" => "#{auto_scaling_group_name}", \
"availability_zones" => "#{availability_zones}", \
"min_size" => "#{min_size}", \
"max_size" => "#{max_size}", \
"default_cooldown" => "#{default_cooldown}", \
"desired_capacity" => "#{desired_capacity}", \
"health_check_grace_period" => "#{health_check_grace_period}", \
"health_check_type" => "#{health_check_type}", \
"load_balancer_names" => "#{load_balancer_names}", \
"placement_group" => "#{placement_group}", \
"tags" => #{tags.to_s}, \
"created_time" => "#{created_time}" \
"target_group_arns" => "#{target_group_arns}" \
}}
  end

private
  def conn
    Aerosol::AWS.auto_scaling
  end

  def create_options
    {
      default_cooldown: default_cooldown,
      desired_capacity: desired_capacity,
      health_check_grace_period: health_check_grace_period,
      health_check_type: health_check_type,
      load_balancer_names: load_balancer_names,
      placement_group: placement_group,
      tags: tags_to_array,
      vpc_zone_identifier: vpc_zone_identifier,
      target_group_arns: target_group_arns
    }.reject { |k, v| v.nil? }
  end

  def tags_to_array
    tags.map do |key, value|
      { key: key, value: value }
    end
  end
end
