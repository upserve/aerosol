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

  describe '#perform_role_assumption' do
    context 'when assume_role is nil' do
      it 'does not change the aws config' do
        expect(Aws).to_not receive(:config)
      end
    end

    context 'when assume_role exists' do
      let(:assume_role) { 'arn:aws:sts::123456789123:role/role-aerosol' }

      before do
        Aerosol::AWS.sts.stub_responses(
          :assume_role,
          credentials: {
            access_key_id: '123',
            secret_access_key: '456',
            session_token: '789',
            expiration: Time.new + 60
          }
        )
      end

      after do
        Aws.config.update(credentials: nil)
      end

      it 'should set the Aws.config[:credentials]' do
        subject.assume_role(assume_role)
        expect { subject.perform_role_assumption }
          .to change { Aws.config[:credentials] }
      end
    end
  end
end
