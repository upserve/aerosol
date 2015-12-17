require 'spec_helper'

describe Aerosol::Deploy do
  let!(:ssh) { double(:ssh) }
  subject { described_class.new(:name => :test) }

  before do
    subject.stub(:ssh).and_return(ssh)
  end

  describe '#migration' do
    context 'by default' do
      its(:migrate?) { should be_true }
    end

    context 'when do_not_migrate! has been called' do
      before { subject.do_not_migrate! }

      its(:migrate?) { should be_false }
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

  describe '#run_post_deploy' do
    context 'with no post_deploy_command' do
      before do
        subject.stub(:post_deploy_command)
      end

      it "doesn't raises an error" do
        expect { subject.run_post_deploy }.to_not raise_error
      end

      it "returns nil" do
        expect(subject.run_post_deploy).to be_nil
      end
    end

    context 'with post_deploy_command' do
      context 'and post_deploy_command runs correctly' do
        before do
          subject.stub(:post_deploy_command).and_return('true')
        end

        it "doesn't raises an error" do
          expect { subject.run_post_deploy }.to_not raise_error
        end

        it "returns true" do
          expect(subject.run_post_deploy).to be_true
        end
      end

      context 'and post_deploy_command runs incorrectly' do
        before do
          subject.stub(:post_deploy_command).and_return('false')
        end

        it 'raises an error' do
          expect { subject.run_post_deploy }.to raise_error
        end
      end
    end
  end

  describe '#local_ssh_ref' do
    context 'when there is no local_ssh' do
      its(:local_ssh_ref) { should eq(ssh) }
    end

    context 'when there is a local_ssh' do
      let!(:local_ssh) { double(:local_ssh) }
      before do
        subject.stub(:local_ssh).and_return(local_ssh)
      end

      its(:local_ssh_ref) { should eq(local_ssh) }
    end
  end

  describe '#generate_ssh_command' do
    let(:ssh_ref) { double(:ssh_ref) }
    let(:launch_configuration) { Aerosol::LaunchConfiguration.new!(name: :test_lc) }
    let(:instance) { Aerosol::Instance.new(launch_configuration: launch_configuration.name) }
    let(:ssh_command) { subject.generate_ssh_command(instance) }

    before do
      allow(instance).to receive(:public_hostname).and_return('hostname.com')
      allow(subject).to receive(:local_ssh_ref).and_return(ssh_ref)
    end

    context 'with a user' do
      before do
        ssh_ref.stub(:user).and_return('ubuntu')
      end

      context 'without a jump server' do
        before do
          ssh_ref.stub(:jump)
        end

        it 'responds with no jump server' do
          expect(ssh_command).to be =~ /ssh .* ubuntu@hostname.com/
        end
      end

      context 'with a jump server' do
        before do
          ssh_ref.stub(:jump).and_return(:user => 'candle', :host => 'example.org')
        end

        it 'responds with a jump server' do
          expect(ssh_command).to be =~ /ssh .* -o 'ProxyCommand=ssh -W %h:%p candle@example\.org' ubuntu@hostname\.com/
        end
      end
    end

    context 'without a user' do
      before do
        ssh_ref.stub(:user)
      end

      context 'without a jump server' do
        before do
          ssh_ref.stub(:jump)
        end

        it 'responds with no user and no jump' do
          expect(ssh_command).to be =~ /ssh .* hostname.com/
        end
      end

      context 'with a jump server' do
        before do
          ssh_ref.stub(:jump).and_return(:user => 'candle', :host => 'example.org')
        end

        it 'responds with no user and a jump server' do
          expect(ssh_command).to be =~ /ssh .* -o 'ProxyCommand=ssh -W %h:%p candle@example\.org' hostname\.com/
        end
      end
    end
  end

  describe '#live_check_url' do
    context 'when SSL is not enabled' do
      subject {
        Aerosol::Deploy.new do
          app_port 5000
          live_check '/test'
        end
      }

      it 'returns an http url' do
        expect(subject.live_check_url).to eq('http://localhost:5000/test')
      end
    end

    context 'when SSL is enabled' do
      subject {
        Aerosol::Deploy.new do
          app_port 4000
          live_check 'check'
          ssl true
        end
      }

      it 'returns an https url' do
        expect(subject.live_check_url).to eq('https://localhost:4000/check')
      end
    end
  end

  describe '#is_alive?' do
    let(:check) { proc { true } }

    context 'when no argument is given' do
      before { subject.is_alive?(&check) }

      it 'returns the current value of is_alive?' do
        expect(subject.is_alive?).to eq(check)
      end
    end

    context 'when a command and block are given' do
      it 'fails' do
        expect { subject.is_alive?('true', &check) }.to raise_error
      end
    end

    context 'when a command is given' do
      let(:command) { 'bash -lc "[[ -e /tmp/up ]]"' }

      it 'sets is_alive? to that value' do
        expect { subject.is_alive?(command) }
          .to change { subject.is_alive? }
          .from(nil)
          .to(command)
      end
    end

    context 'when a block is given' do
      it 'sets is_alive? to that value' do
        expect { subject.is_alive?(&check) }
          .to change { subject.is_alive? }
          .from(nil)
          .to(check)
      end
    end
  end
end
