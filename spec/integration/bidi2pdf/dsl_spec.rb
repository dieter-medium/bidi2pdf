# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::DSL, :chromedriver, :nginx, :session do
  let(:tmp_path) { random_tmp_dir }
  let(:pdf_path) { File.join(tmp_path, "test.pdf") }

  before do
    FileUtils.mkdir_p(tmp_path)
  end

  after do
    FileUtils.rm_f(tmp_path)
  end

  context "with local chrome" do
    it "opens a page and prints it to PDF" do
      described_class.with_tab(headless: true) do |tab|
        tab.open_page(nginx_url("sample.html"))
        tab.wait_until_network_idle
        tab.print(pdf_path)
      end

      expect(File.size(pdf_path)).to be > 1_000
    end
  end

  # in theory, we could connect the networks of chromedriver and nginx testcontainers, but that's not supported be ruby
  # testcontainers, so
  context "with remote chrome" do
    it "opens a page and prints it to PDF" do
      described_class.with_tab(remote_browser_url: session_url, headless: true, chrome_args: chrome_args) do |tab|
        tab.open_page("https://www.selenium.dev/selenium/web/window_switching_tests/simple_page.html")
        tab.wait_until_network_idle
        tab.print(pdf_path)
      end

      expect(File.size(pdf_path)).to be > 1_000
    end
  end
end
