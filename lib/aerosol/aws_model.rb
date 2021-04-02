module Aerosol::AWSModel
  def self.included(base)
    base.instance_eval do
      include Dockly::Util::DSL
      extend ClassMethods

      attr_accessor :from_aws
    end
  end

  def initialize(hash={}, &block)
    self.from_aws = false
    super
  end

  def namespaced_name
    Aerosol.namespace ? "#{Aerosol.namespace}-#{name}" : name.to_s
  end

  def default_identifier
    "#{namespaced_name}-#{Aerosol::Util.git_sha}"
  end

  def create
    raise '#create! must be defined to use #create' unless respond_to?(:create!)
    create! unless exists?
  end

  def destroy
    raise '#destroy! must be defined to use #destroy' unless respond_to?(:destroy!)
    destroy! if exists?
  end

  def exists?
    primary_value = send(self.class.primary_key)
    self.class.exists?(primary_value)
  end

  module ClassMethods
    def primary_key(attr = nil)
      @primary_key = attr unless attr.nil?
      @primary_key
    end

    def aws_attribute(*attrs)
      dsl_attribute(*attrs)
      aws_attributes.merge(attrs)
    end

    def aws_class_attribute(name, klass)
      unless klass.ancestors.include?(Aerosol::AWSModel) || (klass == self)
        raise '.aws_class_attribute requires a Aerosol::AWSModel that is not the current class.'
      end

      dsl_class_attribute(name, klass)
      aws_class_attributes.merge!({ name => klass })
    end

    def exists?(key)
      all.map { |inst| inst.send(primary_key) }.include?(key)
    end

    def all
      raise 'Please define .request_all to use .all' unless respond_to?(:request_all)
      request_all.map { |struct| from_hash(struct.to_hash) }
    end

    def from_hash(hash)
      raise 'To use .from_hash, you must specify a primary_key' if primary_key.nil?
      refs = Hash[aws_class_attributes.map do |name, klass|
        value = klass.instances.values.find do |inst|
          if klass == Aerosol::LaunchTemplate && !hash[:launch_template].nil?
            inst.send(klass.primary_key).to_s == hash[:launch_template][klass.primary_key].to_s unless inst.send(klass.primary_key).nil?
          else
            inst.send(klass.primary_key).to_s == hash[klass.primary_key].to_s unless inst.send(klass.primary_key).nil?
          end
        end
        [name, value]
      end].reject { |k, v| v.nil? }

      instance = new!
      instance.from_aws = true

      aws_attributes.each { |attr| instance.send(attr, hash[attr]) unless hash[attr].nil? }
      refs.each { |name, inst| instance.send(name, inst.name) }
      instance
    end

    def aws_attributes
      @aws_attributes ||= Set.new
    end

    def aws_class_attributes
      @aws_class_attributes ||= {}
    end
  end
end
