require 'spec_helper'

# WARNING if you're re-recording any of these VCRs, you must be running the
# Docker daemon and have the base Image pulled.
describe Docker::Container do
  describe '#to_s' do
    subject { described_class.send(:new, :id => rand(10000).to_s) }

    let(:id) { 'bf119e2' }
    let(:connection) { Docker.connection }
    let(:expected_string) {
      "Docker::Container { :id => #{id}, :connection => #{connection} }"
    }
    before do
      {
        :@id => id,
        :@connection => connection
      }.each { |k, v| subject.instance_variable_set(k, v) }
    end

    its(:to_s) { should == expected_string }
  end

  describe '#json' do
    subject { described_class.create('Cmd' => %w[true], 'Image' => 'base') }
    let(:description) { subject.json }

    it 'returns the description as a Hash', :vcr do
      description.should be_a(Hash)
      description['ID'].should start_with(subject.id)
    end
  end

  describe '#changes' do
    subject { described_class.create('Cmd' => %w[true], 'Image' => 'base') }
    let(:changes) { subject.changes }

    before { subject.tap(&:start).tap(&:wait) }

    it 'returns the changes as an array', :vcr do
      changes.should be_a Array
      changes.should be_all { |change| change.is_a?(Hash) }
      changes.length.should_not be_zero
    end
  end

  describe '#export' do
    subject { described_class.create('Cmd' => %w[rm -rf / --no-preserve-root],
                                     'Image' => 'base') }
    before { subject.start }

    # If you have to re-record this VCR, PLEASE edit it so that it's only ~200
    # lines. This is only because we don't want our gem to be a few hundred
    # megabytes.
    it 'yields each chunk', :vcr do
      first = nil
      subject.export do |chunk|
        first = chunk
        break
      end
      first[257..261].should == "ustar" # Make sure the export is a tar.
    end
  end

  describe '#attach' do
    subject { described_class.create('Cmd' => %w[uname -r], 'Image' => 'base') }

    before { subject.start }

    it 'yields each chunk', :vcr do
      subject.attach { |chunk|
        chunk.should == "3.8.0-25-generic\n"
        break
      }
    end
  end

  describe '#start' do
    subject { described_class.create('Cmd' => %w[true], 'Image' => 'base') }

    it 'starts the container', :vcr do
      subject.start
      described_class.all.map(&:id).should be_any { |id|
        id.start_with?(subject.id)
      }
    end
  end

  describe '#stop' do
    subject { described_class.create('Cmd' => %w[true], 'Image' => 'base') }

    before { subject.tap(&:start).stop }

    it 'stops the container', :vcr do
      described_class.all(:all => true).map(&:id).should be_any { |id|
        id.start_with?(subject.id)
      }
      described_class.all.map(&:id).should be_none { |id|
        id.start_with?(subject.id)
      }
    end
  end

  describe '#kill' do
    subject { described_class.create('Cmd' => ['ls'], 'Image' => 'base') }

    it 'kills the container', :vcr do
      subject.kill
      described_class.all.map(&:id).should be_none { |id|
        id.start_with?(subject.id)
      }
      described_class.all(:all => true).map(&:id).should be_any { |id|
        id.start_with?(subject.id)
      }
    end
  end

  describe '#restart' do
    subject { described_class.create('Cmd' => %w[sleep 50], 'Image' => 'base') }

    before { subject.start }

    it 'restarts the container', :vcr do
      described_class.all.map(&:id).should be_any { |id|
        id.start_with?(subject.id)
      }
      subject.stop
      described_class.all.map(&:id).should be_none { |id|
        id.start_with?(subject.id)
      }
      subject.restart
      described_class.all.map(&:id).should be_any { |id|
        id.start_with?(subject.id)
      }
    end
  end

  describe '#wait' do
    subject { described_class.create('Cmd' => %w[tar nonsense],
                                     'Image' => 'base') }

    before { subject.start }

    it 'waits for the command to finish', :vcr do
      subject.wait['StatusCode'].should == 64
    end

    context 'when an argument is given' do
      subject { described_class.create('Cmd' => %w[sleep 5],
                                       'Image' => 'base') }

      it 'sets the :read_timeout to that amount of time', :vcr do
        subject.wait(6)['StatusCode'].should be_zero
      end

      context 'and a command runs for too long' do
        it 'raises a ServerError', :vcr do
          pending "VCR doesn't like to record errors"
          expect { subject.wait(4) }.to raise_error(Docker::Error::TimeoutError)
        end
      end
    end
  end

  describe '#commit' do
    subject { described_class.create('Cmd' => %w[true], 'Image' => 'base') }
    let(:image) { subject.commit }

    before { subject.start }

    it 'creates a new Image from the  Container\'s changes', :vcr do
      image.should be_a Docker::Image
      image.id.should_not be_nil
    end
  end

  describe '.create' do
    subject { described_class }

    context 'when the body is not a Hash' do
      it 'raises an error' do
        expect { subject.create(:not_a_hash) }
            .to raise_error(Docker::Error::ArgumentError)
      end
    end

    context 'when the Container does not yet exist and the body is a Hash' do
      context 'when the HTTP request does not return a 200' do
        before { Excon.stub({ :method => :post }, { :status => 400 }) }
        after { Excon.stubs.shift }

        it 'raises an error' do
          expect { subject.create }.to raise_error(Docker::Error::ClientError)
        end
      end

      context 'when the HTTP request returns a 200' do
        let(:options) do
          {
            "Hostname"     => "",
            "User"         => "",
            "Memory"       => 0,
            "MemorySwap"   => 0,
            "AttachStdin"  => false,
            "AttachStdout" => false,
            "AttachStderr" => false,
            "PortSpecs"    => nil,
            "Tty"          => false,
            "OpenStdin"    => false,
            "StdinOnce"    => false,
            "Env"          => nil,
            "Cmd"          => ["date"],
            "Dns"          => nil,
            "Image"        => "base",
            "Volumes"      => {},
            "VolumesFrom"  => ""
          }
        end
        let(:container) { subject.create(options) }

        it 'sets the id', :vcr do
          container.should be_a Docker::Container
          container.id.should_not be_nil
          container.connection.should_not be_nil
        end
      end
    end
  end

  describe '.all' do
    subject { described_class }

    context 'when the HTTP response is not a 200' do
      before { Excon.stub({ :method => :get }, { :status => 500 }) }
      after { Excon.stubs.shift }

      it 'raises an error' do
        expect { subject.all }
            .to raise_error(Docker::Error::ServerError)
      end
    end

    context 'when the HTTP response is a 200' do
      before { described_class.create('Cmd' => ['ls'], 'Image' => 'base') }

      it 'materializes each Container into a Docker::Container', :vcr do
        subject.all(:all => true).should be_all { |container|
          container.is_a?(Docker::Container)
        }
        subject.all(:all => true).length.should_not be_zero
      end
    end
  end
end
