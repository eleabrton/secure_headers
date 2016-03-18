require 'rubygems'
require 'rspec'

require File.join(File.dirname(__FILE__), '..', 'lib', 'secure_headers')

if defined?(Coveralls)
  Coveralls.wear!
end

include ::SecureHeaders::StrictTransportSecurity::Constants
include ::SecureHeaders::ContentSecurityPolicy::Constants
include ::SecureHeaders::XFrameOptions::Constants
include ::SecureHeaders::XXssProtection::Constants
include ::SecureHeaders::XContentTypeOptions::Constants
include ::SecureHeaders::XDownloadOptions::Constants
