class Aerosol::Instance
  include Aerosol::AWSModel
  include Dockly::Util::Logger::Mixin

  logger_prefix '[aerosol instance]'
  aws_attribute :availability_zone => 'AvailabilityZone',
                :health_status     => 'HealthStatus',
                :id                => 'InstanceId',
                :lifecycle_state   => 'LifecycleState'
  aws_class_attribute :launch_configuration, Aerosol::LaunchConfiguration
  primary_key :id

  def live?
    describe_again
    instance_state_name == 'running'
  end

  def instance_state_name
    description['instanceState']['name']
  end

  def public_hostname
    description['dnsName']
  end

  def private_ip_address
    description['privateIpAddress']
  end

  def ami
    description['imageId']
  end

  def description
    @description ||= describe!
  end

  def self.request_all
    Aerosol::AWS.auto_scaling
                .describe_auto_scaling_instances
                .body
                .[]('DescribeAutoScalingInstancesResult')
                .[]('AutoScalingInstances')
  end

private
  def describe!
    ensure_present! :id
    attempts ||= 0
    result = Aerosol::AWS.compute.describe_instances('instance-id' => id).body
    result['reservationSet'].first['instancesSet'].first rescue nil
  rescue Fog::Compute::AWS::NotFound => ex
    if attempts < 3
      attempts += 1
      logger.error "#{ex.class}: #{ex.message} - retrying"
      retry
    else
      raise
    end
  end

  def describe_again
    @description = nil
    description
  end
end
