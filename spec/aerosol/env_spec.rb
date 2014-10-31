require 'spec_helper'

describe Aerosol::Env do
  describe '#deploy' do
    let(:name) { "unique_name_#{Time.now.to_i}".to_sym }
    let!(:deploy) { Aerosol.deploy(name) { } }


    it 'adds a deploy to the list of deploys' do
      expect { subject.deploy(name) }
        .to change { subject.deploy }
        .from(nil)
        .to([deploy])
    end
  end
end
