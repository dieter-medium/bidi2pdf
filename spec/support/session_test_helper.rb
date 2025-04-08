# frozen_string_literal: true

module SessionTestHelper
  def create_session(session_url)
    chrome_args = Bidi2pdf::Bidi::Session::DEFAULT_CHROME_ARGS.dup

    # within github actions, the sandbox is not supported, when we start our own container
    # some privileges are not available ???
    if ENV["DISABLE_CHROME_SANDBOX"]
      chrome_args << "--no-sandbox"

      puts "🚨 Chrome sandbox disabled"
    end

    Bidi2pdf::Bidi::Session.new(session_url: session_url, headless: true, chrome_args: chrome_args)
  end
end
