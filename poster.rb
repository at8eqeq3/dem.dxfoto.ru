require 'rubygems'
require 'sinatra/base'
require 'bson'
require 'mongoid'
require 'RMagick'
require 'rvg/rvg'
require 'haml'
require 'rdiscount'
require 'omniauth-vkontakte'
require 'sinatra/flash'
require 'sinatra/r18n'
#require './keys.rb'
include Magick

class Poster < Sinatra::Base
  
  Mongoid.load!("mongoid.yaml")
  enable :sessions
  register Sinatra::Flash
  enable :logging
  use OmniAuth::Builder do
    provider :vkontakte, VK_ID, VK_SECRET
  end
  register Sinatra::R18n
  set :root, File.dirname(__FILE__)
  R18n::I18n.default = 'ru'
  # ======== models ========
  class User
    include Mongoid::Document
    field :uid,  :type => String
    field :name, :type => String
    field :userpic, :type => String
    has_many :images
  end
  class Image
    include Mongoid::Document
    field :slogan,  :type => String
    field :tagline, :type => String
    field :staff_pick, :type => Boolean
    belongs_to :user
    def filename
      self.id.to_s.to_i(16).to_s(36)
    end
  end
  # show index page with all the stuff
  get '/' do
    @images = Image.where(:staff_pick => true).limit(4)
    @images_count = Image.count
    @users_count = User.count
    haml :index
  end
  # show upload form
  get '/create' do
    if session[:uid]
      haml :create
    else
      flash[:error] = t.flash.errors.please_login
      redirect '/'
    end
  end
  # deal with upload
  post '/create' do
    if session[:uid]
      user = User.find_by(:uid => session[:uid])
      begin
        # prepare
        slogan = params["slogan"]
        slogan = slogan[0..34]  if slogan.length > 35
        tagline = params["tagline"]
        tagline = "" if tagline.nil?
        tagline = tagline[0..99] if tagline.length > 100
        # get the image
        logger.info params["image"][:tempfile]
        blob = File.read params["image"][:tempfile]
        #src = Magick::Image.read params["image"][:tempfile]
        src = Magick::Image.from_blob blob
        src = src[0].auto_orient
        src = src.resize_to_fill(642, 432)
        # draw the poster
        rvg = RVG.new(800, 640).viewbox(0, 0, 800, 640) do |canvas|
          canvas.background_fill= 'black'
          canvas.styles :fill => 'white'
          canvas.rect 650, 440, 75, 50
          #canvas.styles :fill => 'black'
          #canvas.rect 644, 434, 78, 53
          canvas.image src, 642, 432, 79, 54
          canvas.text(400, 555) do |sl|
            sl.tspan(slogan).styles(:text_anchor => 'middle',
                                    :font_size => 55,
                                    :font => 'Oranienbaum.ttf',
                                    :fill => 'white')
          end
          canvas.text(400, 600) do |tl|
            tl.tspan(tagline).styles(:text_anchor => 'middle',
                                     :font_size => 32,
                                     :font => 'Cuprum-Regular.ttf',
                                     :fill => 'white')
          end
        end
        # save to DB
        image = user.images.new
        image.slogan = slogan
        image.tagline = tagline
        image.save!
        # save file
        filename = image.filename
        Dir.mkdir("public/uploads/#{filename[0]}") unless Dir.exist?("public/uploads/#{filename[0]}")
        rvg.draw.write "public/uploads/#{filename[0]}/#{filename}.jpg"
        flash[:success] = t.flash.successes.poster_created
        redirect "/image/#{filename}"
      rescue Exception => e
        if !File.file?("public/uploads/#{filename[0]}/#{filename}.jpg")
          image.destroy
        end
        flash[:error] = t.flash.errors.creation_failed
        logger.warn e.message
        redirect '/create'
      end
    else
      flash[:error] = t.flash.errors.please_login
      redirect '/'
    end
  end
  
  # omniauth callback
  %w(get post).each do |method|
    send(method, "/auth/:provider/callback") do
      if env['omniauth.auth']
        @user = User.find_or_create_by(:uid => env['omniauth.auth']['uid'])
        @user.name = env['omniauth.auth']['info']['name']
        @user.userpic = env['omniauth.auth']['info']['image']
        @user.save
        session[:uid] = env['omniauth.auth']['uid']
        session[:name] = env['omniauth.auth']['info']['name']
        flash[:success] = t.flash.successes.welcome(@user.name)
        redirect '/me'
      else
        flash[:error] = t.flash.errors.oauth_error
        redirect '/'
      end
    end
  end
  # current user profile
  get '/me' do
    if session[:uid]
      @user = User.find_by(:uid => session[:uid])
      haml :user
    else
      flash[:error] = t.flash.errors.please_login
      redirect '/'
    end
  end
  # show image
  get '/image/:filename' do |filename|
    begin
      @image = Image.find filename.to_i(36).to_s(16)
      haml :image
    rescue Mongoid::Errors::DocumentNotFound => e
      haml :'404'
    end
  end
  # do search
  get '/search' do
    @images = Image.or({:slogan => /#{params[:term]}/},{:tagline => /#{params[:term]}/}).limit(18)
    haml :search
  end
  get '/about' do
    haml :about
  end
  # deal with 404
  not_found do
    haml :'404'
  end
  run! if app_file == $0
end
