class Aerosol::AutoScaling
  include Aerosol::AWSModel
  include Dockly::Util::Logger::Mixin

  logger_prefix '[slugger auto_scaling]'
  aws_attribute :aws_identifier            => 'AutoScalingGroupName',
                :availability_zones        => 'AvailabilityZones',
                :min_size                  => 'MinSize',
                :max_size                  => 'MaxSize',
                :default_cooldown          => 'DefaultCooldown',
                :desired_capacity          => 'DesiredCapacity',
                :health_check_grace_period => 'HealthCheckGracePeriod',
                :health_check_type         => 'HealthCheckType',
                :load_balancer_names       => 'LoadBalancerNames',
                :placement_group           => 'PlacementGroup',
                :tag_from_array            => 'Tags',
                :created_time              => 'CreatedTime'
  aws_class_attribute :launch_configuration, Aerosol::LaunchConfiguration
  primary_key :aws_identifier

  def initialize(options={}, &block)
    tag = options.delete(:tag)
    super(options, &block)

    tags.merge!(tag) unless tag.nil?

    tags["GitSha"] ||= Aerosol::Util.git_sha
    tags["Deploy"] ||= name.to_s
  end

  def aws_identifier(arg = nil)
    if arg
      raise "You cannot set the aws_identifer directly" unless from_aws
      @aws_identifier = arg
    else
      @aws_identifier || "#{name}-#{Aerosol::Util.git_sha}"
    end
  end

  def exists?
    info "auto_scaling: needed?: #{name}: " +
         "checking for auto scaling group: #{aws_identifier}"
    exists = super
    info "auto scaling: needed?: #{name}: " +
         "#{exists ? 'found' : 'did not find'} auto scaling group: #{aws_identifier}"
    exists
  end

  def create!
    ensure_present! :availability_zones,
                    :launch_configuration,
                    :max_size, :min_size

    info "creating auto scaling group"
    launch_configuration.create
    info self.inspect

    conn.create_auto_scaling_group(aws_identifier, availability_zones,
                                  launch_configuration.aws_identifier,
                                  max_size, min_size,
                                  create_options)
    make_fake_instances
    sleep 10 # TODO: switch to fog models and .wait_for { ready? }
  end

  def destroy!
    info self.inspect
    conn.delete_auto_scaling_group(aws_identifier, 'ForceDelete' => true)
    begin
      launch_configuration.destroy
    rescue
      info "Launch Config: #{launch_configuration} for #{aws_identifier} was not deleted."
    end
  end

  def all_instances
    Aerosol::AWS.auto_scaling
                .describe_auto_scaling_groups('AutoScalingGroupNames' => self.aws_identifier)
                .body
                .[]('DescribeAutoScalingGroupsResult')
                .[]('AutoScalingGroups')
                .first
                .[]('Instances')
                .map { |instance| Aerosol::Instance.from_hash(instance) }
  end

  def tag(val)
    tags.merge!(val)
  end

  def tags
    @tags ||= {}
  end

  def self.request_all
    Aerosol::AWS.auto_scaling
                .describe_auto_scaling_groups
                .body
                .[]('DescribeAutoScalingGroupsResult')
                .[]('AutoScalingGroups')
  end

  def self.latest_for_tag(key, value)
    all.select  { |group| group.tags[key] == value }
       .sort_by { |group| group.created_time }
       .last
  end

private
  def conn
    Aerosol::AWS.auto_scaling
  end

  def create_options
    {
      'DefaultCooldown' => default_cooldown,
      'DesiredCapacity' => desired_capacity,
      'HealthCheckGracePeriod' => health_check_grace_period,
      'HealthCheckType' => health_check_type,
      'LoadBalancerNames' => load_balancer_names,
      'PlacementGroup' => placement_group,
      'Tags' => tags
    }.reject { |k, v| v.nil? }
  end

  def tag_from_array(ary)
    if ary.is_a? Hash
      ary.each do |key, value|
        tag key => value
      end
    else
      ary.each do |hash|
        tag hash['Key'] => hash['Value']
      end
    end
  end

  # Unfortunately, Fog does not create fake instances after an auto scaling
  # group is created.
  def make_fake_instances
    return unless Fog.mock?

    asg_instances = []
    all_instances = []
    min_size.times do |n|
      instance_id = Fog::AWS::Mock.instance_id
      asg_instances << {
        'AvailabilityZone'        => availability_zones,
        'HealthStatus'            => 'Good',
        'InstanceId'              => instance_id,
        'LifecycleState'          => 'Pending',
        'LaunchConfigurationName' => launch_configuration.aws_identifier
      }

      all_instances << {
        'amiLaunchIndex'      => n,
        'architecture'        => 'i386',
        'blockDeviceMapping'  => [],
        'clientToken'         => 'FAKE_CLIENT_TOKEN',
        'dnsName'             => 'not-a-real-hostname',
        'ebsOptimized'        => false,
        'hypervisor'          => 'xen',
        'imageId'             => launch_configuration.ami,
        'instanceId'          => instance_id,
        'instanceState'       => { 'code' => 0, 'name' => 'not pending?' },
        'instanceType'        => launch_configuration.instance_type,
        'kernelId'            => launch_configuration.kernel_id || Fog::AWS::Mock.kernel_id,
        'keyName'             => launch_configuration.key_name,
        'launchTime'          => Time.now,
        'monitoring'          => { 'state' => false },
        'placement'           => { 'availabilityZone' => availability_zones,
                                   'groupName'        => self.aws_identifier,
                                   'tenancy'          => 'default' },
        'privateDnsName'      => nil,
        'productCodes'        => [],
        'reason'              => nil,
        'rootDeviceType'      => 'instance-store',
        'virtualizationType'  => 'paravirtual',
        'groupIds'            => [],
        'groupSet'            => launch_configuration.security_groups,
        'iamInstanceProfile'  => launch_configuration.iam_role,
        'networkInterfaces'   => [],
        'ownerId'             => nil,
        'privateIpAddress'    => nil,
        'reservationId'       => Fog::AWS::Mock.reservation_id,
        'stateReason'         => {},
        'ipAddress'           => Fog::AWS::Mock.ip_address,
        'privateIpAddress'    => Fog::AWS::Mock.private_ip_address
      }
    end
    Aerosol::AWS.auto_scaling.data[:auto_scaling_groups][aws_identifier]
                             .merge!('Instances' => asg_instances)
    all_instances.each do |instance|
      Aerosol::AWS.compute.data[:instances][instance['instanceId']] = instance
    end
  end
end
