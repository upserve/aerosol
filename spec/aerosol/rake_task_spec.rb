require 'spec_helper'

describe 'Rake' do
  describe 'load' do
    before do
      Aerosol::Util.stub(:git_sha)
    end

    context 'when the aerosol.rb file does not exist' do
      before do
        File.stub(:exist?).and_return(false)
      end

      it 'raises an error' do
        lambda { Rake::Task['aerosol:load'].invoke }.should raise_error(RuntimeError, 'No aerosol.rb found!')
      end
    end
  end
end
