require 'fpm/package/docker'
describe FPM::Package::Docker do

  describe '#input' do

    subject{
      described_class.new(client: client)
    }

    after(:each) do
      subject.cleanup_staging
      subject.cleanup_build
    end

    let(:client){
      client = double('client')
      allow(client).to receive(:changes).with('foo').and_return(changes)
      client
    }

    context 'trivial case' do
      let(:changes){
        [
          { "Path"=> "/dev" },
          { "Path"=> "/dev/sda" },
          { "Path"=> "/tmp" },
          { "Path"=> "/tmp/foo" },
          { "Path"=> "/usr/bin/foo" }
        ]
      }

      it 'ignores changes in /dev and /tmp' do
        expect(client).to receive(:broken_symlinks?).and_return(false)
        expect(client).to receive(:copy).with('foo','/usr/bin/foo', a_string_matching(%r!usr/bin/foo!), Hash)
        subject.input('foo')
      end

      it 'ignores changes in /dev and /tmp' do
        expect(client).to receive(:broken_symlinks?).and_return(true)
        expect(client).to receive(:copy).with('foo','/usr/bin', a_string_matching(%r!usr/bin!), Hash)
        subject.input('foo')
      end
    end

    context 'with excludes set' do
      let(:changes){
        [
          { "Path"=> "/a" },
          { "Path"=> "/a/bar" },
          { "Path"=> "/b" },
          { "Path"=> "/b/bar" }
        ]
      }

      it 'drops whole directories if requested' do
        expect(client).to receive(:broken_symlinks?).and_return(false)
        expect(client).to receive(:copy).with('foo','/b/bar', a_string_matching(%r!b/bar\z!), Hash)
        subject.attributes[:excludes] = [
          'a'
        ]
        subject.input('foo')
      end

      it 'drops whole directories if requested' do
        expect(client).to receive(:broken_symlinks?).and_return(true)
        expect(client).to receive(:copy).with('foo','/b', a_string_matching(%r!b\z!), Hash)
        subject.attributes[:excludes] = [
          'a'
        ]
        subject.input('foo')
      end
    end

    context 'broken docker symlink behavior' do
      let(:changes){
        [
          { "Path"=> "/a" },
          { "Path"=> "/a/bar" },
          { "Path"=> "/b" },
          { "Path"=> "/b/bar" }
        ]
      }

      it 'is fixed by downloading enclosing directories' do
        expect(client).to receive(:broken_symlinks?).and_return(true)
        options = {chown: false, only: {'/a/bar'=> true, '/b/bar' => true }}
        expect(client).to receive(:copy).with('foo','/a', a_string_matching(%r!a!), options)
        expect(client).to receive(:copy).with('foo','/b', a_string_matching(%r!b!), options)
        subject.input('foo')
      end
    end
  end
end