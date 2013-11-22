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
    end
  end
end
