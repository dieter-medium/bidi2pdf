# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class SetTabCookie
        include Base

        class << self
          attr_writer :time_provider

          def time_provider
            @time_provider ||= -> { Time.now }
          end
        end

        attr_reader :name, :value, :domain, :path, :secure, :http_only, :same_site, :ttl, :browsing_context_id

        def initialize(name:,
                       value:,
                       domain:,
                       browsing_context_id:,
                       path: "/",
                       secure: true,
                       http_only: false,
                       same_site: "strict",
                       ttl: 30)
          @name = name
          @value = value
          @domain = domain
          @path = path
          @secure = secure
          @http_only = http_only
          @same_site = same_site
          @ttl = ttl
          @browsing_context_id = browsing_context_id
        end

        def expiry
          self.class.time_provider.call.to_i + ttl
        end

        def method_name
          "storage.setCookie"
        end

        def params
          {
            cookie: {
              name: name,
              value: {
                type: "string",
                value: value
              },
              domain: domain,
              path: path,
              secure: secure,
              httpOnly: http_only,
              sameSite: same_site,
              expiry: expiry
            },
            partition: {
              type: "context",
              context: browsing_context_id
            }
          }.compact
        end
      end
    end
  end
end
