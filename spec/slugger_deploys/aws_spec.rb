require 'spec_helper'

describe SluggerDeploys::AWS do
  subject { SluggerDeploys::AWS }

  describe '#reset_cache!' do
    before do
      subject.instance_variable_set(:@auto_scaling, double)
      subject.instance_variable_set(:@compute, double)
    end

    it 'sets @auto_scaling to nil' do
      expect { subject.reset_cache! }
          .to change { subject.instance_variable_get(:@auto_scaling) }
          .to(nil)
    end

    it 'sets @compute to nil' do
      expect { subject.reset_cache! }
          .to change { subject.instance_variable_get(:@compute) }
          .to(nil)
    end
  end
end
