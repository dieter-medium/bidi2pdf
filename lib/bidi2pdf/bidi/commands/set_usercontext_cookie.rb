# frozen_string_literal: true

module Bidi2pdf
  module Bidi
    module Commands
      class SetUsercontextCookie < SetTabCookie
        include Base

        attr_reader :user_context_id, :source_origin

        def initialize(name:,
                       value:,
                       domain:,
                       user_context_id:,
                       source_origin:,
                       path: "/",
                       secure: true,
                       http_only: false,
                       same_site: "strict",
                       ttl: 30)
          super(name: name, value: value,
                domain: domain,
                path: path,
                secure: secure,
                http_only: http_only,
                same_site: same_site,
                ttl: ttl,
                browsing_context_id: nil)

          @user_context_id = user_context_id
          @source_origin = source_origin
        end

        def expiry
          Time.now.to_i + ttl
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
              type: "storageKey",
              userContext: user_context_id,
              sourceOrigin: source_origin
            }
          }.compact
        end
      end
    end
  end
end
