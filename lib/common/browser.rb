# encoding: UTF-8

require 'common/typhoeus_cache'
require 'common/browser/actions'
require 'common/browser/options'

class Browser
  extend  Browser::Actions
  include Browser::Options

  OPTIONS = [
    :basic_auth,
    :cache_ttl,
    :max_threads,
    :user_agent,
    :proxy,
    :proxy_auth,
    :request_timeout,
    :connect_timeout,
    :cookie
  ]

  @@instance = nil

  attr_reader :hydra, :cache_dir

  attr_accessor :referer, :cookie

  # @param [ Hash ] options
  #
  # @return [ Browser ]
  def initialize(options = {})
    @cache_dir   = options[:cache_dir] || CACHE_DIR + '/browser'

    # sets browser defaults
    browser_defaults
    # load config file
    conf = options[:config_file]
    load_config(conf) if conf
    # overrides defaults with user supplied values (overwrite values from config)
    override_config(options)

    unless @hydra
      @hydra = Typhoeus::Hydra.new(max_concurrency: self.max_threads)
    end

    @cache = TyphoeusCache.new(@cache_dir)
    @cache.clean

    Typhoeus::Config.cache = @cache
  end

  private_class_method :new

  # @param [ Hash ] options
  #
  # @return [ Browser ]
  def self.instance(options = {})
    unless @@instance
      @@instance = new(options)
    end
    @@instance
  end

  def self.reset
    @@instance = nil
  end

  #
  # sets browser default values
  #
  def browser_defaults
    @max_threads = 20
    # 10 minutes, at this time the cache is cleaned before each scan. If this value is set to 0, the cache will be disabled
    @cache_ttl = 600
    @request_timeout = 60 # 60s
    @connect_timeout = 10 # 10s
    @user_agent = "WPScan v#{WPSCAN_VERSION} (http://wpscan.org)"
  end

  #
  # If an option was set but is not in the new config_file
  # it's value is kept
  #
  # @param [ String ] config_file
  #
  # @return [ void ]
  def load_config(config_file = nil)

    if File.symlink?(config_file)
      raise '[ERROR] Config file is a symlink.'
    else
      data = JSON.parse(File.read(config_file))
    end

    OPTIONS.each do |option|
      option_name = option.to_s
      unless data[option_name].nil?
        self.send(:"#{option_name}=", data[option_name])
      end
    end

  end

  # @param [ String ] url
  # @param [ Hash ] params
  #
  # @return [ Typhoeus::Request ]
  def forge_request(url, params = {})
    Typhoeus::Request.new(url, merge_request_params(params))
  end

  # @param [ Hash ] params
  #
  # @return [ Hash ]
  def merge_request_params(params = {})
    params = Browser.append_params_header_field(
      params,
      'User-Agent',
      @user_agent
    )

    if @proxy
      params = params.merge(proxy: @proxy)

      if @proxy_auth
        params = params.merge(proxyauth: @proxy_auth)
      end
    end

    if @basic_auth
      params = Browser.append_params_header_field(
        params,
        'Authorization',
        @basic_auth
      )
    end

    params.merge!(referer: referer)
    params.merge!(timeout: @request_timeout) if @request_timeout
    params.merge!(connecttimeout: @connect_timeout) if @connect_timeout

    # Used to enable the cache system if :cache_ttl > 0
    params.merge!(cache_ttl: @cache_ttl) unless params.has_key?(:cache_ttl)

    # Prevent infinite self redirection
    params.merge!(maxredirs: 3) unless params.has_key?(:maxredirs)

    # Disable SSL-Certificate checks
    params.merge!(ssl_verifypeer: false)
    params.merge!(ssl_verifyhost: 0)

    params.merge!(cookiejar: @cache_dir + '/cookie-jar')
    params.merge!(cookiefile: @cache_dir + '/cookie-jar')
    params.merge!(cookie: @cookie) if @cookie

    params
  end

  private

  # @param [ Hash ] params
  # @param [ String ] field
  # @param [ Mixed ] field_value
  #
  # @return [ Array ]
  def self.append_params_header_field(params = {}, field, field_value)
    if !params.has_key?(:headers)
      params = params.merge(:headers => { field => field_value })
    elsif !params[:headers].has_key?(field)
      params[:headers][field] = field_value
    end
    params
  end

end
