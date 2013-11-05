require 'spec_helper'

describe 'Rake' do
  describe 'load' do
    before do
      SluggerDeploys::Util.stub(:git_sha)
    end

    context 'when the deploys.rb file does not exist' do
      before do
        File.stub(:exist?).and_return(false)
      end

      it 'raises an error' do
        lambda { Rake::Task['deploys:load'].invoke }.should raise_error(RuntimeError, 'No deploys.rb found!')
      end
    end
  end
end
