#!/usr/bin/env ruby
# Coding: UTF-8

require "ipaddr"

class PatliteArgumentError < ArgumentError; end

configure :development do
  use BetterErrors::Middleware
  BetterErrors.application_root = settings.root
end

configure do
  log_path = Pathname(settings.root) + "log"
  FileUtils.makedirs(log_path)
  logger = Logger.new("#{log_path}/#{settings.environment}.log", "daily")
  logger.instance_eval { alias :write :<< unless respond_to?(:write) }
  use Rack::CommonLogger, logger

  enable :prefixed_redirects
  set :haml, format: :html5
  set :scss, style: :expanded

  set :allowed_hosts, %w(127.0.0.0/8
                         10.0.0.0/8
                         172.16.0.0/12
                         192.168.0.0/16
                      ).map{|x| IPAddr.new(x) }

  set :allowed_commands, %w(alert clear status test) # doclear dotest
  set :allowed_alert_options, %i(r y g z sec)
  set :allowed_clear_options, %i(p z)

  set :patlite_host,  ENV["PATLITE_HOST"]
  set :patlite_ruser, ENV["PATLITE_RUSER"] || "patlite"
end

helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end

  def patlite_command(command, options, dry_run: false)
    if not settings.allowed_commands.include?(command)
      raise "Invalid command: #{command}"
    end

    options_str = ""
    error_keys = []

    if command == "alert"
      default_options = { r: 9, y: 9, g: 9, z: 9, sec: 0 }

      matcher = {
        r: /^[01239]$/,
        y: /^[01239]$/,
        g: /^[01239]$/,
        z: /^[012349]$/,
        sec: /^[0-9]{,2}$/
      }

      options = default_options.merge(options).inject(Hash.new) do |result, (key, value)|
        if not matcher[key] === value.to_s
          error_keys << key
        else
          result[key] = value.to_s
        end

        result
      end

      options_str = "%s%s%s00%s %s" % options.values_at(*settings.allowed_alert_options)

    elsif command == "clear"
      matcher = {
        p: /^[01]$/,
        z: /^[01]$/,
      }

      options = options.inject(Hash.new) do |result, (key, value)|
        if not matcher[key] === value.to_s
          error_keys << key
        else
          result[key] = value.to_s
        end

        result
      end

      options_str = options.select{|key, value| value == 1}.keys.map{|x| "-#{x}" }.join(?\s)
    end

    if not error_keys.empty?
      raise PatliteArgumentError, "%s %s invalid" % [error_keys.join(?\s), error_keys.size == 1 ? "is" : "are"]
    end

    return if dry_run

    command_str = "rsh -l #{settings.patlite_ruser} #{settings.patlite_host} #{command} #{options_str}"
    logger.info "Cmd: #{command_str}"

    result = `#{command_str}`
  end

  def protected!(user, pass)
    unless authorized?(user, pass)
      response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?(user, pass)
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [user, pass]
  end
end

get "/?" do
  @lamp_options  = %i(r y g)
  @buzzer_option = :z
  @sec_option    = :sec

  haml :index
end

before "/webhook" do
  halt 403 if not settings.allowed_hosts.any?{|range| range === request.ip }
end

post "/webhook" do
  protected!("user", "password")

  request.body.rewind
  params = JSON.parse(request.body.read)

  logger.info "Received webhook: `#{params}`"

  case params["event"]
  when "sample"
    patlite_command("test")
  when "alert"
    status = params.dig("alert", "status")

    case status
    when "critical"
      patlite_command("alert", r: 1, z: 1, sec: 2)
    when "warning"
      patlite_command("alert", y: 1, z: 1, sec: 2)
    when "ok"
      patlite_command("alert", g: 1, z: 1, sec: 2)
    end
  end
end

before %r{/cmd/(?<command>.+)} do
  if not settings.allowed_commands.include?(params[:command])
    not_found
  end
end

get %r{/cmd/(?<command>.+)} do
  command = params[:command]

  options = settings.allowed_alert_options.inject(Hash.new) do |hash, key|
    hash[key] = params[key] if not params[key].nil?
    hash
  end

  begin
    patlite_command(command, options, dry_run: true)
  rescue PatliteArgumentError => e
    result = { status: "error", command: command, parameter: options}
    logger.error result

    halt 412, result.to_json
  end

  logger.info "Execute: command: #{command}, options: #{options}"

  patlite_result = patlite_command(command, options)

  result = { status: "success", command: command, patlite_result: patlite_result }
  logger.info result

  result.to_json
end

not_found do
  { error: "not found" }.to_json
end

get "/css/*" do
  file_name = params[:splat].first
  views =  Pathname(settings.views)

  if File.exists?(views + "css" + file_name)
    send_file views + "css" + file_name
  elsif File.exists?(views + "scss" + file_name.sub(%r{.css$}, ".scss"))
    scss :"scss/#{file_name.sub(%r{.css$}, "")}"
  else
    halt 404
  end
end
