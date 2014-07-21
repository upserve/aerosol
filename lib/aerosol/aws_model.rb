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

  def default_identifier
    iden = Aerosol.namespace ? "#{Aerosol.namespace}-" : ""
    iden += "#{name}-#{Aerosol::Util.git_sha}"
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

    def aws_attribute(hash)
      dsl_attribute(*hash.keys)
      aws_attributes.merge!(hash)
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
      request_all.map { |hash| from_hash(hash) }
    end

    def from_hash(hash)
      raise 'To use .from_hash, you must specify a primary_key' if primary_key.nil?
      refs = Hash[aws_class_attributes.map do |name, klass|
        [name, klass.instances.values.find do |inst|
          inst.send(klass.primary_key) &&
            (inst.send(klass.primary_key) == hash[klass.aws_attributes[klass.primary_key]])
        end]
      end].reject { |k, v| v.nil? }

      instance = new!
      instance.from_aws = true

      aws_attributes.each { |k, v| instance.send(k, hash[v]) unless hash[v].nil? }
      refs.each { |name, inst| instance.send(name, inst.name) }
      instance
    end

    def aws_attributes
      @aws_attributes ||= {}
    end

    def aws_class_attributes
      @aws_class_attributes ||= {}
    end
  end
end
