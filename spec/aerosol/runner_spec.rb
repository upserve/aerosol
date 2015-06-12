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
    before do
      allow(Aerosol::Util).to receive(:git_sha).and_return('1')
      Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
        launch_configurations: [
          {
            launch_configuration_name: 'launch_config-1',
            image_id: 'ami-1234567',
            instance_type: 'm1.large'
          },
          {
            launch_configuration_name: 'launch_config-2',
            image_id: 'ami-1234567',
            instance_type: 'm1.large'
          },
          {
            launch_configuration_name: 'launch_config-3',
            image_id: 'ami-1234567',
            instance_type: 'm1.large'
          }
        ],
        next_token: nil
      })
      Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_groups, {
        auto_scaling_groups: [
          {
            auto_scaling_group_name: 'auto_scaling_group-1',
            launch_configuration_name: 'launch_config-1',
            min_size: 1,
            max_size: 1,
            desired_capacity: 1,
            default_cooldown: 300,
            availability_zones: ['us-east-1a'],
            health_check_type: 'EC2',
            created_time: Time.new(2015, 01, 01, 01, 01, 01),
            tags: [{ key: 'Deploy', value: 'auto_scaling_group'}, { key: 'GitSha', value: '1' }]
          },
          {
            auto_scaling_group_name: 'auto_scaling_group-2',
            launch_configuration_name: 'launch_config-2',
            min_size: 1,
            max_size: 1,
            desired_capacity: 1,
            default_cooldown: 300,
            availability_zones: ['us-east-1a'],
            health_check_type: 'EC2',
            created_time: Time.new(2015, 01, 01, 01, 01, 01),
            tags: [{ key: 'Deploy', value: 'auto_scaling_group'}, { key: 'GitSha', value: '2'}]
          },
          {
            auto_scaling_group_name: 'auto_scaling_group-3',
            launch_configuration_name: 'launch_config-3',
            min_size: 1,
            max_size: 1,
            desired_capacity: 1,
            default_cooldown: 300,
            availability_zones: ['us-east-1a'],
            health_check_type: 'EC2',
            created_time: Time.new(2015, 01, 01, 01, 01, 01),
            tags: [{ key: 'Deploy', value: 'auto_scaling_group'}, { key: 'GitSha', value: '3'}]
          }
        ],
        next_token: nil
      })

      Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_instances, {
        auto_scaling_instances: 3.times.map do |i|
          {
            instance_id: "i-#{123456+i}",
            auto_scaling_group_name: "auto_scaling_group-#{i+1}",
            launch_configuration_name: "launch_config-#{i+1}"
          }
        end,
        next_token: nil
      })

      Aerosol::Deploy.new! do
        name :old_instances_deploy
        auto_scaling do
          name :auto_scaling_group
          min_size 1
          max_size 1

          launch_configuration do
            name :launch_config
            image_id 'fake-ami'
            instance_type 'm1.large'
          end
        end
      end
    end

    let!(:all_lcs) { Aerosol::LaunchConfiguration.all }
    let!(:all_asgs) { Aerosol::AutoScaling.all }

    let(:all_instance_ids) { Aerosol::Instance.all.map(&:instance_id).sort }
    let(:old_instance_ids) { subject.old_instances.map(&:instance_id).sort }

    let(:asg1) { all_asgs[0] }
    let(:asg2) { all_asgs[1] }
    let(:asg3) { all_asgs[2] }
    let(:asg1_instances) { asg1.launch_configuration.all_instances.map(&:instance_id) }
    let(:combined_instances) {
      asg2.launch_configuration.all_instances + asg3.launch_configuration.all_instances
    }
    let(:combined_instance_ids) { combined_instances.map(&:instance_id).sort }

    let(:all_asgs_instances) {
      [asg1, asg2, asg3].map(&:launch_configuration).map(&:all_instances).flatten
    }
    let(:all_asgs_instance_ids) { all_asgs_instances.map(&:instance_id).sort }

    it 'returns each instance that is not a member of the current auto scaling group' do
      subject.with_deploy :old_instances_deploy do
        expect(old_instance_ids).to eq(combined_instance_ids)
        subject.old_instances.length.should == 2
      end
    end

    it 'does not include any of the current auto scaling group\'s instances' do
      subject.with_deploy :old_instances_deploy do
        asg1.launch_configuration.all_instances.should be_none { |inst|
          old_instance_ids.include?(inst.instance_id)
        }
      end
    end

    it 'does not modify the existing instances' do
      expect(all_instance_ids).to eq(all_asgs_instance_ids)
      subject.with_deploy :old_instances_deploy do
        expect(subject.new_instances.map(&:instance_id).sort).to eq(asg1_instances.sort)
      end
    end
  end

  describe '#new_instances' do
    let!(:lc7) do
      Aerosol::LaunchConfiguration.new! do
        name :lc7
        image_id 'fake-ami-how-scandalous'
        instance_type 'm1.large'
        stub(:sleep)
      end
    end
    let!(:asg7) do
      Aerosol::AutoScaling.new! do
        name :asg7
        availability_zones 'us-east-1'
        min_size 0
        max_size 3
        launch_configuration :lc7
        stub(:sleep)
      end
    end
    let!(:instance1) do
      Aerosol::Instance.from_hash(
        {
          instance_id: 'z0',
          launch_configuration_name: lc7.launch_configuration_name
        }
      )
    end
    let!(:instance2) do
      double(:launch_configuration => double(:launch_configuration_name => 'lc7-8891022'))
    end
    let!(:instance3) do
      double(:launch_configuration => double(:launch_configuration_name => 'lc0-8891022'))
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
               :instance_id => "test#{i}")
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

  describe '#start_tailing_logs' do
    let(:ssh) { double(:ssh) }
    let(:instance) { double(Aerosol::Instance, instance_id: '2') }
    let(:command) { 'sudo tail -f /var/log/syslog' }
    let(:tail_logs) { true }
    let(:log_files) { ['/var/log/syslog'] }

    before do
      allow(subject).to receive(:tail_logs).and_return(tail_logs)
      allow(subject).to receive(:log_files).and_return(log_files)
    end

    context 'when there are log_files' do
      context 'when a log fork is already made' do
        let(:old_log_fork) { double(:old_log_fork) }

        it 'keeps the old one' do
          subject.log_pids[instance.instance_id] = old_log_fork
          expect(subject.start_tailing_logs(ssh, instance)).to be(old_log_fork)
        end
      end

      context 'when no log fork exists' do
        let(:new_log_fork) { double(:new_log_fork) }

        it 'makes a new one' do
          expect(subject).to receive(:ssh_fork).with(command, ssh, instance) {
            new_log_fork
          }
          expect(subject.start_tailing_logs(ssh, instance)).to be(new_log_fork)
        end
      end
    end

    context 'when there is no log_files' do
      let(:log_files) { [] }

      it 'does not call ssh_fork' do
        expect(subject).to_not receive(:ssh_fork)
      end
    end

    context 'when tail_logs is false' do
      let(:tail_logs) { false }

      it 'does not call ssh_fork' do
        expect(subject).to_not receive(:ssh_fork)
      end
    end
  end

  describe '#ssh_fork', :local do
    let(:ssh) { Aerosol::Connection.new(user: `whoami`.strip, host: 'www.doesntusethis.com') }
    let(:instance) { double(Aerosol::Instance, instance_id: '1', public_hostname: 'localhost') }
    let(:ssh_fork) {
      subject.ssh_fork(command, ssh, instance)
    }
    context 'when no error is raised' do
      let(:command) { 'echo "hello"; echo "bye"' }

      it 'should make a new fork that SSHs and runs a command' do
        expect(subject).to receive(:fork).and_yield do |&block|
          expect(subject).to receive(:debug).exactly(5).times
          block.call
        end
        ssh_fork
      end
    end

    context 'when an error is raised' do
      let(:command) { ['test','ing'] }

      it 'logs the errors' do
        expect(subject).to receive(:fork).and_yield do |&block|
          expect(subject).to receive(:error).twice
          block.call
        end
        ssh_fork
      end
    end
  end

  describe '#stop_app' do
    let!(:lc) do
      Aerosol::LaunchConfiguration.new! do
        name :stop_app_launch_config
        image_id 'stop-app-ami-123'
        instance_type 'm1.large'
        stub(:sleep)
      end
    end
    let!(:asg) do
      Aerosol::AutoScaling.new! do
        name :stop_app_auto_scaling_group
        availability_zones 'us-east-1'
        min_size 5
        max_size 5
        launch_configuration :stop_app_launch_config
        stub(:sleep)
      end
    end
    let!(:session) { double(:session) }
    let!(:deploy) do
      s = session
      Aerosol::Deploy.new! do
        auto_scaling :stop_app_auto_scaling_group
        name :stop_app_deploy
        ssh :stop_app_ssh do
          user 'dad'
          stub(:with_connection).and_yield(s)
        end
        stop_command 'mkdir lol'
      end
    end

    it 'sshs into each old instance and calls the stop command' do
      Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
        launch_configurations: [
          {
            launch_configuration_name: 'stop_app_launch_config-123456',
            image_id: 'stop-app-ami-123',
            instance_type: 'm1.large'
          }
        ],
        next_token: nil
      })
      Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_groups, {
        auto_scaling_groups: [
          {
            auto_scaling_group_name: 'stop_app_auto_scaling_group-123456',
            min_size: 5,
            max_size: 5,
            desired_capacity: 5,
            launch_configuration_name: 'stop_app_launch_config-123456',
            tags: [
              {
                key: 'GitSha',
                value: '123456',
              },
              {
                key: 'Deploy',
                value: 'stop_app_auto_scaling_group'
              }
            ]
          }
        ],
        next_token: nil
      })
      Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_instances, {
        auto_scaling_instances: 5.times.map do |n|
          { launch_configuration_name: 'stop_app_launch_config-123456' }
        end
      })
      Aerosol::AWS.compute.stub_responses(:describe_instances, {
        reservations: [
          {
            instances: [
              {
                public_dns_name: 'test'
              }
            ]
          }
        ]
      })
      session.should_receive(:exec!).with(deploy.stop_command).exactly(5).times
      session.should_receive(:loop).exactly(5).times
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
