# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module NetworkEventFormatters
      class NetworkEventHtmlFormatter
        include NetworkEventFormatterUtils

        def render(events)
          return unless Bidi2pdf.network_events_logger.info?

          <<~HTML
            <!DOCTYPE html>
            <html lang="en" data-bs-theme="light">
            <head>
              <meta charset="UTF-8">
              <title>Network Events</title>
              <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
              <style>
                body { font-family: monospace; padding: 2rem; }
                .event { background: var(--bs-body-bg); border: 1px solid var(--bs-border-color); padding: 1rem; margin-bottom: 2rem; border-radius: .5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
                .bar-container { position: relative; height: 20px; background: var(--bs-secondary-bg); border-radius: 4px; }
                .bar { position: absolute; top: 0; height: 100%; background-color: #0d6efd; opacity: 0.8; }
                .toc a { text-decoration: none; display: block; margin-bottom: 0.5rem; }

                @media print {
                  .no-break {
                    page-break-inside: avoid;
                  }
            #{"    "}
            #{"     "}
                  .form-select, .form-label, #theme-select {
                    display: none !important; /* Hide theme selector when printing */
                  }
                }

                .event {
                  word-break: break-word;
                  overflow-wrap: anywhere;
                }
              </style>
              <script>
                function toggleTheme(value) {
                  document.documentElement.setAttribute('data-bs-theme', value);
                }
              </script>
            </head>
            <body>
              <h1>Network Events</h1>
              <div class="mb-4">
                <label for="theme-select" class="form-label">Theme:</label>
                <select id="theme-select" class="form-select w-auto d-inline-block" onchange="toggleTheme(this.value)">
                  <option value="light">Light</option>
                  <option value="dark">Dark</option>
                </select>
              </div>

              <h2>Index</h2>
              <div class="toc mb-4">
                #{events.map.with_index { |e, i| toc_entry(e, i) }.join("\n")}
              </div>

              #{events.map.with_index { |e, i| render_event(e, i) }.join("\n")}
            </body>
            </html>
          HTML
        end

        def toc_entry(event, index)
          "<a href=\"#event-#{index}\">[#{index + 1}] #{event.http_method} #{event.url}</a>"
        end

        # rubocop: disable Metrics/AbcSize
        def render_event(event, index)
          timing = parse_timing(event)
          duration = event.duration_seconds || 0
          duration_str = event.in_progress? ? "in progress" : "#{duration}s"
          status = event.http_status_code || "?"
          method = event.http_method || "?"
          start = format_timestamp(event.start_timestamp)
          finish = event.end_timestamp ? format_timestamp(event.end_timestamp) : "..."
          bytes = event.bytes_received ? format_bytes(event.bytes_received) : "N/A"
          bars = render_timing_bars(timing)
          displayed_url = shorten_url(event.url)

          <<~HTML
            <div class="event no-break" id="event-#{index}">
              <div><strong>Request:</strong> #{method} #{displayed_url}</div>
              <div><strong>Status:</strong> HTTP #{status}</div>
              <div><strong>State:</strong> #{event.state}</div>
              <div><strong>Start:</strong> #{start}</div>
              <div><strong>End:</strong> #{finish}</div>
              <div><strong>Duration:</strong> #{duration_str}</div>
              <div><strong>Received:</strong> #{bytes}</div>
              #{bars}
            </div>
          HTML
        end

        # rubocop: enable Metrics/AbcSize

        def render_timing_bars(timing)
          return "" if timing.empty?

          max_ms = timing.map { |t| t[:ms] }.max
          scale = max_ms.zero? ? 0 : 100.0 / max_ms

          bars = timing.map do |t|
            width = (t[:ms] * scale).clamp(1, 100).round(2)
            <<~HTML
              <div>
                <small>#{t[:label]} (#{t[:ms]} ms)</small>
                <div class="bar-container mb-2">
                  <div class="bar" style="width: #{width}%"></div>
                </div>
              </div>
            HTML
          end

          "<div class=\"mt-3\"><strong>Timing Waterfall</strong>#{bars.join}</div>"
        end
      end
    end
  end
end
