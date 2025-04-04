# frozen_string_literal: true

require "spec_helper"
require "net/http"

RSpec.describe Bidi2pdf::ChromedriverManager, :chromedriver_update do
  let(:manager) { described_class.new(port: 0, headless: true) }

  before(:all) do
    tmp_dir = File.join(File.expand_path("../../tmp", __dir__), "chromedriver", SecureRandom.hex(8))
    FileUtils.mkdir_p(tmp_dir)

    Chromedriver::Binary.configure do |config|
      config.logger.level = Logger::INFO

      @old_install_dir = config.install_dir

      config.install_dir = tmp_dir
    end
  end

  after(:all) do
    Chromedriver::Binary.configure do |config|
      config.logger.level = Logger::INFO

      current_dir = config.install_dir

      FileUtils.rm_rf(current_dir)

      config.install_dir = @old_install_dir
    end
  end

  after do
    manager.stop if manager.pid
  end

  describe "#start" do
    context "when starting chromedriver with real update" do
      before do
        @pid = manager.start
      end

      it "returns a PID as an Integer" do
        expect(@pid).to be_a(Integer)
      end

      it "assigns a usable port greater than 0" do
        expect(manager.port).to be > 0
      end

      it "spawns a live chromedriver process" do
        expect(@pid).to be_alive_process
      end

      it "creates a session object" do
        expect(manager.session).not_to be_nil
      end
    end
  end

  describe "#stop" do
    context "when chromedriver is started" do
      before do
        @pid = manager.start
      end

      it "starts a live chromedriver process before stopping" do
        expect(@pid).to be_alive_process
      end

      it "sets pid to nil after stop" do
        manager.stop
        expect(manager.pid).to be_nil
      end

      it "clears the session after stop" do
        manager.stop
        expect(manager.session).to be_nil
      end

      it "terminates the chromedriver process after stop" do
        manager.stop
        expect(@pid).not_to be_alive_process
      end
    end
  end
end
