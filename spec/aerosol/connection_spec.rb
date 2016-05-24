require 'spec_helper'

describe Aerosol::Connection do
  describe '#with_connection' do
    context 'when at least one of the required fields is missing' do
      it 'raises an error' do
        expect { subject.with_connection }.to raise_error
      end
    end

    context 'when all of the required fields are present' do
      subject do
        Aerosol::Connection.new do
          name :lil_joey_pumpkins
          host 'www.aol.com'
          user 'steve_case'
        end
      end

      context 'when the jump host is nil' do
        it 'logs in directly' do
          Net::SSH.should_receive(:start)
          subject.with_connection
        end
      end

      context 'when the jump host is present' do
        let(:gateway) { double(:gateway) }
        before do
          subject.jump :host => 'my-jump-host', :user => 'my-user'
        end

        it 'goes through the jump host' do
          Net::SSH::Gateway.stub(:new).and_return(gateway)
          gateway.should_receive(:ssh)
          gateway.should_receive(:shutdown!)
          subject.with_connection
        end
      end

      context 'when the host is an instance' do
        let(:public_hostname) { nil }
        let(:host) { Aerosol::Instance.new }
        subject do
          Aerosol::Connection.new.tap do |inst|
            inst.name :connection_for_tim_horton
            inst.user 'tim_horton'
            inst.host host
          end
        end

        before do
          allow(host).to receive(:public_hostname).and_return(public_hostname)
          allow(host).to receive(:private_ip_address).and_return('152.60.94.125')
        end

        context 'when the public_hostname is present' do
          let(:public_hostname) { 'example.com' }
          it 'returns the public_hostname' do
            Net::SSH.should_receive(:start).with(public_hostname, 'tim_horton', timeout: 20)
            subject.with_connection
          end
        end

        context 'when the public_hostname is nil' do
          it 'returns the private_ip_address' do
            Net::SSH.should_receive(:start).with('152.60.94.125', 'tim_horton', timeout: 20)
            subject.with_connection
          end
        end
      end

      context 'when the host is passed into with_connection' do
        let(:public_hostname) { nil }
        let(:host) { Aerosol::Instance.new }
        subject do
          Aerosol::Connection.new.tap do |inst|
            inst.name :connection_for_tim_horton
            inst.user 'tim_horton'
          end
        end

        before do
          allow(host).to receive(:public_hostname).and_return(public_hostname)
          allow(host).to receive(:private_ip_address).and_return('152.60.94.125')
        end

        context 'when the public_hostname is present' do
          let(:public_hostname) { 'example.com' }
          it 'returns the public_hostname' do
            Net::SSH.should_receive(:start).with(public_hostname, 'tim_horton', timeout: 20)
            subject.with_connection(host)
          end
        end

        context 'when the public_hostname is an empty string' do
          let(:public_hostname) { '' }
          it 'returns the private_ip_address' do
            Net::SSH.should_receive(:start).with('152.60.94.125', 'tim_horton', timeout: 20)
            subject.with_connection(host)
          end
        end

        context 'when the public_hostname is nil' do
          it 'returns the private_ip_address' do
            Net::SSH.should_receive(:start).with('152.60.94.125', 'tim_horton', timeout: 20)
            subject.with_connection(host)
          end
        end
      end
    end
  end
end
