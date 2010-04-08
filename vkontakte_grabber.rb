require 'rubygems'
require 'mechanize'
require 'yajl'
require 'iconv'

class VkontakteGrabber
  attr_reader :agent
  
  def initialize(email, password)
    @agent = Mechanize.new
    page = agent.get('http://vkontakte.ru')
    login_form = page.form('login')
    login_form.email = email
    login_form.pass = password
    #login & redirect
    @agent.submit( @agent.submit(login_form, login_form.buttons.first).forms.first ) 
  end

  def get_friends(user_id=nil)
    if user_id.nil?
      get_friends_list_from_page @agent.get('http://vkontakte.ru/friends.php').body
    else
      get_friends_list_from_page @agent.get("http://vkontakte.ru/friends.php?id=#{user_id}").body
    end
  end

private
  def get_friends_list_from_page page_body
    friends_json_match = page_body.match(/^\s+var friendsData = (\{.+\});$/)
   
    return {} if friends_json_match.nil?

    friends_json = Iconv.conv('UTF-8//IGNORE//TRANSLIT', 'CP1251', friends_json_match[1]).gsub("'","\"").gsub(/\b(\d+):/,"\"\\1\":").gsub(/[\x00-\x19]/," ")

    return Yajl::Parser.parse friends_json
    begin
    rescue Yajl::ParserError
      puts 'JSON parsing error. Offending line stored into parse_error.json'
      File.open('parse_error.json','w') {|f| f.write friends_json}
      {}
    end
  end
end
