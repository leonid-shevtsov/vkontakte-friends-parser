require 'rubygems'
require 'mechanize'
require 'logger'
require 'iconv'

# monkeypatching, for version 0.9.3 to use headers parameter
class WWW::Mechanize
  def post(url, query={}, headers={})
    node = {}
    # Create a fake form
    class << node
      def search(*args); []; end
    end
    node['method'] = 'POST'
    node['enctype'] = 'application/x-www-form-urlencoded'

    form = Form.new(node)
    query.each { |k,v|
      if v.is_a?(IO)
        form.enctype = 'multipart/form-data'
        ul = Form::FileUpload.new(k.to_s,::File.basename(v.path))
        ul.file_data = v.read
        form.file_uploads << ul
      else
        form.fields << Form::Field.new(k.to_s,v)
      end
    }
    post_form(url, form, headers)
  end
end

class String
  def to_cp1251
    Iconv.conv('cp1251//IGNORE//TRANSLIT','UTF-8',self)
  end
end

class VkontakteException < Exception
end

class VkontakteNotAuthorizedException < VkontakteException
end

module VkontakteUrlBuilder
  DOMAIN='http://vkontakte.ru'
  
  def root_url
    "#{VkontakteUrlBuilder::DOMAIN}"
  end

  def profile_url(id=nil)
    "#{VkontakteUrlBuilder::DOMAIN}/profile.php#{id.nil? ? '' : "?id=#{id.to_i}"}"
  end
end

# Provides interface to a Vkontakte user session.
# Since this requires an active user, I've decided to put all actions against the user in this class
#
# TODO login is painfully slow: implement stored sessions
# TODO implement cached pages
# TODO error handling
class VkontakteClient
  include VkontakteUrlBuilder

  HEADERS = {
    'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language' => 'ru,en-us;q=0.7,en;q=0.3',
    'Accept-Charset' =>  'ISO-8859-1,utf-8;q=0.7,*;q=0.7',
    'Pragma' => 'no-cache',
    'Cache-Control' => 'no-cache',
  }

  attr_reader :email, :id

  def initialize email, password
    @email = email
    
    #create Mechanize agent
    @agent = WWW::Mechanize.new
    File.unlink('mechanize.log')
    @agent.log = Logger.new('mechanize.log')
    @agent.user_agent = some_user_agent

    #get login form
    page = get(root_url)
    login_form = page.form('login')
    login_form.email = @email
    login_form.pass = password

    #login & redirect
    @agent.submit( @agent.submit(login_form, login_form.buttons.first).forms.first ) 

    #get my id, check that we're actually logged in
    @id = @agent.page.at('#mid')['value'] rescue nil
    raise VkontakteNotAuthorizedException.new if @id.nil? or @id==''
  end

  # Sets the user's status
  def set_status(new_status)
    profile_page = get_profile_page
    activity_hash = profile_page.at('#activityhash')['value'] rescue nil
    
    #Referer MUST be "/profile.php"
    ajax_post(profile_url, :setactivity => new_status.to_s, :activityhash => activity_hash).inspect
  end

  # Returns true, if the current session is valid
  def session_valid?
    get(profile_url).uri.to_s == profile_url
  end

  def user
    @user ||= VkontakteUser.new(@id)
  end
private

  # Page loading. Probably I'll implement caching here
  def get(url, params={})
    @agent.get(url,params)
  end

  def post(url, params={})
    @agent.post(url,params,VkontakteClient::HEADERS)
  end

  def ajax_post(url, params={})
    @agent.post(url,params,VkontakteClient::HEADERS.merge({
      'X-Requested-With' => 'XMLHttpRequest', 
      'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8'
    }))
  end

  # Page loading 
  def get_profile_page id=nil
    get(profile_url(id))
  end

  #TODO return random user agents
  def some_user_agent
    "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.1.3) Gecko/20090920 Firefox/3.5.3 (Swiftfox)"
  end
end

vk = VkontakteClient.new 'me@galvanic.com.ua',                                                                                                                'ikdtifs'

#vk.set_status 'Русский привет из Ruby - в правильной кодировке!'
vk.set_status 'Hello?'
