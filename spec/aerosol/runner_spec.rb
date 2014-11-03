require 'spec_helper'

describe Aerosol::Runner do
  describe '#with_deploy' do
    before { subject.instance_variable_set(:@deploy, :original_deploy) }

    context 'when the name is not one of the listed deploys' do
      it 'raises an error and does not change the @deploy variable' do
        subject.deploy.should == :original_deploy
        expect { subject.with_deploy(:not_a_real_deploy) {} }.to raise_error
        subject.deploy.should == :original_deploy
      end
    end

    context 'when the name is a valid deploy' do
      before do
        Aerosol::Deploy.new!(:name => :my_deploy)
      end

      it 'sets @deploy to that deploy' do
        subject.with_deploy(:my_deploy) do
          subject.deploy.should be_a Aerosol::Deploy
          subject.deploy.name.should == :my_deploy
        end
      end

      it 'changes @deploy back after' do
        expect { subject.with_deploy(:my_deploy) {} }.to_not change { subject.deploy }
      end
    end
  end

  describe '#run_migration' do
    let(:db_conn) { double(:db_conn) }

    before do
      ENV['RAILS_ENV'] = 'production'
      subject.stub(:db_conn).and_return(db_conn)
    end

    context 'when the deploy is nil' do
      before { subject.instance_variable_set(:@deploy, nil) }

      it 'raises an error' do
        expect { subject.run_migration }.to raise_error
      end
    end

    context 'context when the deploy is present' do
      let!(:connection) { Aerosol::Connection.new!(:name => :run_migration_conn) }
      let!(:deploy) { Aerosol::Deploy.new!(:name => :run_migration_deploy, :ssh => :run_migration_conn) }

      before { subject.instance_variable_set(:@deploy, deploy) }

      context 'and #do_not_migrate! has been called on it' do
        before { subject.deploy.do_not_migrate! }

        it 'does nothing' do
          connection.should_not_receive(:with_connection)
          subject.run_migration
        end
      end

      context 'and #do_not_migrate! has not been called on it' do
        context 'but the rails env is nil' do
          before { ENV['RAILS_ENV'] = nil }

          it 'raises an error' do
            expect { subject.run_migration }.to raise_error
          end
        end

        context 'and the rails env is set' do
          let(:session) { double(:session) }
          let(:port) { 50127 }
          let(:conf) do
            {
              ENV['RAILS_ENV'] =>
                {
                  'database' => 'daddybase',
                  'host' => 'http://www.geocities.com/spunk1111/',
                  'port' => 8675309
                }
            }
          end

          before do
            subject.stub(:random_open_port).and_return(port)
            File.stub(:read)
            ERB.stub_chain(:new, :result)
            YAML.stub(:load).and_return(conf)
            deploy.stub_chain(:migration_ssh, :with_connection).and_yield(session)
            Process.stub(:waitpid).and_return { 1 }
            Process::Status.any_instance.stub(:exitstatus) { 0 }
            session.stub(:loop).and_yield
          end

          it 'forwards the database connection and runs the migration' do
            session.stub_chain(:forward, :local)
                   .with(port,
                         conf['production']['host'],
                         conf['production']['port'])
            ActiveRecord::Base.stub(:establish_connection)
            ActiveRecord::Migrator.stub(:migrate)
                                  .with(%w[db/migrate])
            subject.run_migration
          end
        end
      end
    end
  end

  describe '#old_instances' do
    let!(:asg1) do
      Aerosol::AutoScaling.new! do
        name :old_instances_asg_1
        availability_zones 'us-east-1'
        min_size 5
        max_size 5
        tag 'Deploy' => 'old_instances_deploy', 'GitSha' => 1
        launch_configuration do
          ami 'fake-ami'
          instance_type 'm1.large'
          stub(:sleep)
        end
        stub(:sleep)
      end.tap(&:create)
    end
    let!(:asg2) do
      Aerosol::AutoScaling.new! do
        name :old_instances_asg_2
        availability_zones 'us-east-1'
        min_size 5
        max_size 5
        launch_configuration do
          ami 'fake-ami'
          instance_type 'm1.large'
          stub(:sleep)
        end
        tag 'Deploy' => 'old_instances_deploy', 'GitSha' => 2
        stub(:sleep)
      end.tap(&:create)
    end
    let!(:asg3) do
      Aerosol::AutoScaling.new! do
        name :old_instances_asg_3
        availability_zones 'us-east-1'
        min_size 5
        max_size 5
        tag 'Deploy' => 'old_instances_deploy', 'GitSha' => 3
        launch_configuration do
          ami 'fake-ami'
          instance_type 'm1.large'
          stub(:sleep)
        end
        stub(:sleep)
      end.tap(&:create)
    end

    let!(:deploy) do
      Aerosol::Deploy.new! do
        name :old_instances_deploy
        auto_scaling :old_instances_asg_1
      end
    end

    before(:all) { Aerosol::AutoScaling.all.map(&:destroy) }

    it 'returns each instance that is not a member of the current auto scaling group' do
      subject.with_deploy :old_instances_deploy do
        subject.old_instances.map(&:id).sort.should ==
          (asg2.launch_configuration.all_instances + asg3.launch_configuration.all_instances).map(&:id).sort
        subject.old_instances.length.should == 10
      end
    end

    it 'does not include any of the current auto scaling group\'s instances' do
      subject.with_deploy :old_instances_deploy do
        asg1.launch_configuration.all_instances.should be_none { |inst|
          subject.old_instances.map(&:id).include?(inst.id)
        }
      end
    end

    it 'does not modify the existing instances' do
      Aerosol::Instance.all.map(&:id).sort.should ==
        [asg1, asg2, asg3].map(&:launch_configuration).map(&:all_instances).flatten.map(&:id).sort
      subject.with_deploy :old_instances_deploy do
        subject.new_instances.map(&:id).sort.should == asg1.all_instances.map(&:id).sort
      end
    end
  end

  describe '#new_instances' do
    let!(:lc7) do
      Aerosol::LaunchConfiguration.new! do
        name :lc7
        ami 'fake-ami-how-scandalous'
        instance_type 'm1.large'
        stub(:sleep)
      end.tap(&:create)
    end
    let!(:asg7) do
      Aerosol::AutoScaling.new! do
        name :asg7
        availability_zones 'us-east-1'
        min_size 0
        max_size 3
        launch_configuration :lc7
        stub(:sleep)
      end.tap(&:create)
    end
    let!(:instance1) do
      Aerosol::Instance.from_hash(
        {
          'InstanceId' => 'z0',
          'LaunchConfigurationName' => lc7.aws_identifier
        }
      )
    end
    let!(:instance2) do
      double(:launch_configuration => double(:aws_identifier => 'lc7-8891022'))
    end
    let!(:instance3) do
      double(:launch_configuration => double(:aws_identifier => 'lc0-8891022'))
    end

    let!(:deploy) do
      Aerosol::Deploy.new! do
        name :new_instances_deploy
        auto_scaling :asg7
      end
    end

    before do
      Aerosol::Instance.stub(:all).and_return([instance1, instance2, instance3])
    end
    it 'returns each instance that is a member of the current launch config' do
      subject.with_deploy :new_instances_deploy do
        subject.new_instances.should == [instance1]
      end
    end
  end

  describe '#wait_for_new_instances' do
    let(:instances) do
      3.times.map do |i|
        double(:instance,
               :public_hostname => 'not-a-real-hostname',
               :id => "test#{i}")
      end
    end
    let(:timeout_length) { 0.01 }
    let!(:deploy) do
      timeout = timeout_length
      Aerosol::Deploy.new! do
        name :wait_for_new_instances_deploy
        is_alive? { is_site_live }
        instance_live_grace_period timeout
        stub(:sleep)
      end
    end
    let(:action) do
      subject.with_deploy(:wait_for_new_instances_deploy) { subject.wait_for_new_instances }
    end

    before do
      subject.stub(:healthy?).and_return(healthy)
      subject.stub(:sleep)
      subject.stub(:new_instances).and_return(instances)
    end

    context 'when all of the new instances eventually return a 200' do
      let(:timeout_length) { 1 }
      let(:healthy) { true }
      let(:is_site_live) { true }

      it 'does nothing' do
        expect { action }.to_not raise_error
      end
    end

    context 'when at least one of the instances never returns a 200' do
      let(:healthy) { false }
      let(:is_site_live) { false }

      it 'raises an error' do
        expect { action }.to raise_error
      end
    end

    context 'when getting new instances takes too long' do
      let(:healthy) { true }
      let(:is_site_live) { false }
      before do
        allow(subject).to receive(:new_instances) { sleep 10 }
      end

      it 'raises an error' do
        expect { action }.to raise_error
      end
    end
  end

  describe '#stop_app' do
    let!(:lc) do
      Aerosol::LaunchConfiguration.new! do
        name :stop_app_launch_config
        ami 'stop-app-ami-123'
        instance_type 'm1.large'
        stub(:sleep)
      end.tap(&:create)
    end
    let!(:asg) do
      Aerosol::AutoScaling.new! do
        name :stop_app_auto_scaling_group
        availability_zones 'us-east-1'
        min_size 5
        max_size 5
        launch_configuration :stop_app_launch_config
        stub(:sleep)
      end.tap(&:create)
    end
    let!(:instances) { Aerosol::Instance.all.select { |instance| instance.ami == lc.ami } }
    let!(:session) { double(:session) }
    let!(:deploy) do
      s = session
      Aerosol::Deploy.new! do
        name :stop_app_deploy
        ssh :stop_app_ssh do
          user 'dad'
          stub(:with_connection).and_yield(s)
        end
        stop_command 'mkdir lol'
      end
    end

    it 'sshs into each old instance and calls the stop command' do
      session.should_receive(:exec!).with(deploy.stop_command).exactly(5).times
      session.should_receive(:loop).exactly(5).times
      subject.stub(:old_instances).and_return(instances)
      subject.with_deploy :stop_app_deploy do
        subject.stop_app
      end
    end
  end

  describe '#old_auto_scaling_groups/#new_auto_scaling_groups' do
    let!(:asg1) do
      Aerosol::AutoScaling.new! do
        name :destroy_old_asgs_auto_scaling_group_1
        availability_zones 'us-east-1'
        min_size 0
        max_size 3
        tag 'Deploy' => 'destroy_old_asgs_deploy', 'GitSha' => '1e7b3cd'
        stub(:sleep)
        stub(:aws_identifier).and_return(1)
      end
    end
    let!(:asg2) do
      Aerosol::AutoScaling.new! do
        name :destroy_old_asgs_auto_scaling_group_2
        availability_zones 'us-east-1'
        min_size 0
        max_size 3
        tag 'Deploy' => 'destroy_old_asgs_deploy', 'GitSha' => '1234567'
        stub(:sleep)
        stub(:aws_identifier).and_return(2)
      end
    end
    let!(:asg3) do
      Aerosol::AutoScaling.new! do
        name :destroy_old_asgs_auto_scaling_group_3
        availability_zones 'us-east-1'
        min_size 0
        max_size 5
        tag 'Deploy' => 'not-part-of-this-app', 'GitSha' => '1e7b3cd'
        stub(:sleep)
        stub(:aws_identifier).and_return(3)
      end
    end

    let!(:deploy) do
      Aerosol::Deploy.new! do
        name :destroy_old_asgs_deploy
        auto_scaling :destroy_old_asgs_auto_scaling_group_1
      end
    end

    before do
      subject.instance_variable_set(:@deploy, deploy)
      Aerosol::AutoScaling.stub(:all).and_return([asg1, asg2, asg3])
    end

    it 'returns the old and new groups from this app' do
      subject.old_auto_scaling_groups.should == [asg2]
      subject.new_auto_scaling_groups.should == [asg1]
    end
  end
end
