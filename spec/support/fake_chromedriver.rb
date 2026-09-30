# frozen_string_literal: true

# A chromedriver behind ChromedriverApi's injectable HTTP, for ChromeSweeper specs: GET /sessions
# lists +sessions+, DELETE removes one (404 when it is not there, +failing+ ids answer 500).
FakeChromedriver = Struct.new(:sessions, :failing) do
  def initialize(sessions = [], failing = []) = super

  def call(method, url)
    return [200, JSON.generate("value" => sessions.map { |id| { "id" => id, "capabilities" => { "webSocketUrl" => "ws://x/#{id}" } } })] if method == :get

    id = url.split("/").last
    return [500, ""] if failing.include?(id)

    sessions.delete(id) ? [200, ""] : [404, ""]
  end

  def api(session_url) = Bidi2pdf::ChromedriverApi.new(session_url, http: self)
end

# Stands in for ChromeSweeper::Inspector attaching to each session: +ages+ (seconds, nil = unknown),
# +hung+ ids, renderer +cpu+ times; a recorded session is aged by its registry time against +time+
# (a one-element array holding "now"), as the real Inspector does.
FakeSessionInspector = Struct.new(:ages, :hung, :cpu, :time) do
  def self.build(ages = {}, time: [Time.now.to_f]) = new(ages, [], {}, time)

  def examine(entry, recorded_at: nil)
    Bidi2pdf::ChromeSweeper::Inspector::SessionInfo.new(
      id: entry.id, age: recorded_at ? time.first - recorded_at : ages[entry.id], source: :tab, tabs: 1,
      responsive: !hung.include?(entry.id), cpu_times: cpu.fetch(entry.id, {})
    )
  end
end
