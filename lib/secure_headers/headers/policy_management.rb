module SecureHeaders
  module PolicyManagement
    def self.included(base)
      base.extend(ClassMethods)
    end

    MODERN_BROWSERS = %w(Chrome Opera Firefox)
    DEFAULT_VALUE = "default-src https:".freeze
    DEFAULT_CONFIG = { default_src: %w(https:) }.freeze
    HEADER_NAME = "Content-Security-Policy".freeze
    REPORT_ONLY = "Content-Security-Policy-Report-Only".freeze
    HEADER_NAMES = [HEADER_NAME, REPORT_ONLY]
    DATA_PROTOCOL = "data:".freeze
    BLOB_PROTOCOL = "blob:".freeze
    SELF = "'self'".freeze
    NONE = "'none'".freeze
    STAR = "*".freeze
    UNSAFE_INLINE = "'unsafe-inline'".freeze
    UNSAFE_EVAL = "'unsafe-eval'".freeze

    # leftover deprecated values that will be in common use upon upgrading.
    DEPRECATED_SOURCE_VALUES = [SELF, NONE, UNSAFE_EVAL, UNSAFE_INLINE, "inline", "eval"].map { |value| value.delete("'") }.freeze

    DEFAULT_SRC = :default_src
    CONNECT_SRC = :connect_src
    FONT_SRC = :font_src
    FRAME_SRC = :frame_src
    IMG_SRC = :img_src
    MEDIA_SRC = :media_src
    OBJECT_SRC = :object_src
    SANDBOX = :sandbox
    SCRIPT_SRC = :script_src
    STYLE_SRC = :style_src
    REPORT_URI = :report_uri

    DIRECTIVES_1_0 = [
      DEFAULT_SRC,
      CONNECT_SRC,
      FONT_SRC,
      FRAME_SRC,
      IMG_SRC,
      MEDIA_SRC,
      OBJECT_SRC,
      SANDBOX,
      SCRIPT_SRC,
      STYLE_SRC,
      REPORT_URI
    ].freeze

    BASE_URI = :base_uri
    CHILD_SRC = :child_src
    FORM_ACTION = :form_action
    FRAME_ANCESTORS = :frame_ancestors
    PLUGIN_TYPES = :plugin_types

    # These are directives that do not inherit the default-src value. This is
    # useful when calling #combine_policies.
    NON_DEFAULT_SOURCES = [
      BASE_URI,
      FORM_ACTION,
      FRAME_ANCESTORS,
      PLUGIN_TYPES,
      REPORT_URI
    ]

    DIRECTIVES_2_0 = [
      DIRECTIVES_1_0,
      BASE_URI,
      CHILD_SRC,
      FORM_ACTION,
      FRAME_ANCESTORS,
      PLUGIN_TYPES
    ].flatten.freeze

    # All the directives currently under consideration for CSP level 3.
    # https://w3c.github.io/webappsec/specs/CSP2/
    MANIFEST_SRC = :manifest_src
    REFLECTED_XSS = :reflected_xss
    DIRECTIVES_3_0 = [
      DIRECTIVES_2_0,
      MANIFEST_SRC,
      REFLECTED_XSS
    ].flatten.freeze

    # All the directives that are not currently in a formal spec, but have
    # been implemented somewhere.
    BLOCK_ALL_MIXED_CONTENT = :block_all_mixed_content
    UPGRADE_INSECURE_REQUESTS = :upgrade_insecure_requests
    DIRECTIVES_DRAFT = [
      BLOCK_ALL_MIXED_CONTENT,
      UPGRADE_INSECURE_REQUESTS
    ].freeze

    SAFARI_DIRECTIVES = DIRECTIVES_1_0

    FIREFOX_UNSUPPORTED_DIRECTIVES = [
      BLOCK_ALL_MIXED_CONTENT,
      CHILD_SRC,
      PLUGIN_TYPES
    ].freeze

    FIREFOX_DIRECTIVES = (
      DIRECTIVES_2_0 + DIRECTIVES_DRAFT - FIREFOX_UNSUPPORTED_DIRECTIVES
    ).freeze

    CHROME_DIRECTIVES = (
      DIRECTIVES_2_0 + DIRECTIVES_DRAFT
    ).freeze

    ALL_DIRECTIVES = [DIRECTIVES_1_0 + DIRECTIVES_2_0 + DIRECTIVES_3_0 + DIRECTIVES_DRAFT].flatten.uniq.sort

    # Think of default-src and report-uri as the beginning and end respectively,
    # everything else is in between.
    BODY_DIRECTIVES = ALL_DIRECTIVES - [DEFAULT_SRC, REPORT_URI]

    VARIATIONS = {
      "Chrome" => CHROME_DIRECTIVES,
      "Opera" => CHROME_DIRECTIVES,
      "Firefox" => FIREFOX_DIRECTIVES,
      "Safari" => SAFARI_DIRECTIVES,
      "Other" => CHROME_DIRECTIVES
    }.freeze

    OTHER = "Other".freeze

    DIRECTIVE_VALUE_TYPES = {
      BASE_URI                  => :source_list,
      BLOCK_ALL_MIXED_CONTENT   => :boolean,
      CHILD_SRC                 => :source_list,
      CONNECT_SRC               => :source_list,
      DEFAULT_SRC               => :source_list,
      FONT_SRC                  => :source_list,
      FORM_ACTION               => :source_list,
      FRAME_ANCESTORS           => :source_list,
      FRAME_SRC                 => :source_list,
      IMG_SRC                   => :source_list,
      MANIFEST_SRC              => :source_list,
      MEDIA_SRC                 => :source_list,
      OBJECT_SRC                => :source_list,
      PLUGIN_TYPES              => :source_list,
      REFLECTED_XSS             => :string,
      REPORT_URI                => :source_list,
      SANDBOX                   => :string,
      SCRIPT_SRC                => :source_list,
      STYLE_SRC                 => :source_list,
      UPGRADE_INSECURE_REQUESTS => :boolean
    }.freeze

    CONFIG_KEY = :csp
    STAR_REGEXP = Regexp.new(Regexp.escape(STAR))
    HTTP_SCHEME_REGEX = %r{\Ahttps?://}

    WILDCARD_SOURCES = [
      UNSAFE_EVAL,
      UNSAFE_INLINE,
      STAR,
      DATA_PROTOCOL,
      BLOB_PROTOCOL
    ].freeze

    META_CONFIGS = [
      :report_only,
      :preserve_schemes
    ].freeze

    module ClassMethods
      # Public: generate a header name, value array that is user-agent-aware.
      #
      # Returns a default policy if no configuration is provided, or a
      # header name and value based on the config.
      def make_header(config, user_agent)
        header = new(config, user_agent)
        [header.name, header.value]
      end

      # Public: Validates each source expression.
      #
      # Does not validate the invididual values of the source expression (e.g.
      # script_src => h*t*t*p: will not raise an exception)
      def validate_config!(config)
        return if config.nil? || config == OPT_OUT
        raise ContentSecurityPolicyConfigError.new(":default_src is required") unless config[:default_src]
        config.each do |key, value|
          if META_CONFIGS.include?(key)
            raise ContentSecurityPolicyConfigError.new("#{key} must be a boolean value") unless boolean?(value) || value.nil?
          else
            validate_directive!(key, value)
          end
        end
      end

      # Public: determine if merging +additions+ will cause a change to the
      # actual value of the config.
      #
      # e.g. config = { script_src: %w(example.org google.com)} and
      # additions = { script_src: %w(google.com)} then idempotent_additions? would return
      # because google.com is already in the config.
      def idempotent_additions?(config, additions)
        return false if config == OPT_OUT
        config.to_s == combine_policies(config, additions).to_s
      end

      # Public: combine the values from two different configs.
      #
      # original - the main config
      # additions - values to be merged in
      #
      # raises an error if the original config is OPT_OUT
      #
      # 1. for non-source-list values (report_only, block_all_mixed_content, upgrade_insecure_requests),
      # additions will overwrite the original value.
      # 2. if a value in additions does not exist in the original config, the
      # default-src value is included to match original behavior.
      # 3. if a value in additions does exist in the original config, the two
      # values are joined.
      def combine_policies(original, additions)
        if original == OPT_OUT
          raise ContentSecurityPolicyConfigError.new("Attempted to override an opt-out CSP config.")
        end

        original = original.dup if original.frozen?

        # in case we would be appending to an empty directive, fill it with the default-src value
        additions.keys.each do |directive|
          unless original[directive] || !source_list?(directive) || NON_DEFAULT_SOURCES.include?(directive)
            original[directive] = original[:default_src]
          end
        end

        # merge the two hashes. combine (instead of overwrite) the array values
        # when each hash contains a value for a given key.
        original.merge(additions) do |directive, lhs, rhs|
          if source_list?(directive)
            (lhs.to_a + rhs.to_a).compact.uniq
          else
            rhs
          end
        end.reject { |_, value| value.nil? || value == [] } # this mess prevents us from adding empty directives.
      end

      private

      def source_list?(directive)
        DIRECTIVE_VALUE_TYPES[directive] == :source_list
      end

      # Private: Validates that the configuration has a valid type, or that it is a valid
      # source expression.
      def validate_directive!(key, value)
        case ContentSecurityPolicy::DIRECTIVE_VALUE_TYPES[key]
        when :boolean
          unless boolean?(value)
            raise ContentSecurityPolicyConfigError.new("#{key} must be a boolean value")
          end
        when :string
          unless value.is_a?(String)
            raise ContentSecurityPolicyConfigError.new("#{key} Must be a string. Found #{config.class}: #{config} value")
          end
        else
          validate_source_expression!(key, value)
        end
      end

      # Private: validates that a source expression:
      # 1. has a valid name
      # 2. is an array of strings
      # 3. does not contain any depreated, now invalid values (inline, eval, self, none)
      #
      # Does not validate the invididual values of the source expression (e.g.
      # script_src => h*t*t*p: will not raise an exception)
      def validate_source_expression!(key, value)
        unless ContentSecurityPolicy::ALL_DIRECTIVES.include?(key)
          raise ContentSecurityPolicyConfigError.new("Unknown directive #{key}")
        end

        unless value.is_a?(Array) && value.compact.all? { |v| v.is_a?(String) }
          raise ContentSecurityPolicyConfigError.new("#{key} must be an array of strings")
        end

        value.each do |source_expression|
          if ContentSecurityPolicy::DEPRECATED_SOURCE_VALUES.include?(source_expression)
            raise ContentSecurityPolicyConfigError.new("#{key} contains an invalid keyword source (#{source_expression}). This value must be single quoted.")
          end
        end
      end

      def boolean?(value)
        value.is_a?(TrueClass) || value.is_a?(FalseClass)
      end
    end
  end
end
