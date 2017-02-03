::SecureHeaders::Configuration.configure do |config|
  config.hsts = { :max_age => 10.years.to_i.to_s, :include_subdomains => false }
  config.x_frame_options = 'DENY'
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = {:value => 0}
  config.x_permitted_cross_domain_policies = 'none'
  csp = {
    :default_src => "self",
    :script_src => "self nonce",
    :report_uri => 'somewhere',
    :script_hash_middleware => true,
    :enforce => false # false means warnings only
  }

  config.csp = csp
end
