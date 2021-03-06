if exists("g:loaded_vimux_ruby_test") || &cp
  finish
endif
let g:loaded_vimux_ruby_test = 1

if !has("ruby")
  finish
end

if !exists("g:vimux_ruby_cmd_unit_test")
  let g:vimux_ruby_cmd_unit_test = "ruby"
endif
if !exists("g:vimux_ruby_cmd_all_tests")
  let g:vimux_ruby_cmd_all_tests = "ruby"
endif
if !exists("g:vimux_ruby_cmd_context")
  let g:vimux_ruby_cmd_context = "ruby"
endif

command RunAllRubyTests :call s:RunAllRubyTests()
command RunAllRailsTests :call s:RunAllRailsTests()
command RunRubyFocusedTest :call s:RunRubyFocusedTest()
command RunRailsFocusedTest :call s:RunRailsFocusedTest()
command RunRubyFocusedContext :call s:RunRubyFocusedContext()

function s:RunAllRubyTests()
  ruby RubyTest.new.run_all(false)
endfunction

function s:RunAllRailsTests()
  ruby RubyTest.new.run_all(true)
endfunction

function s:RunRubyFocusedTest()
  ruby RubyTest.new.run_test(false)
endfunction

function s:RunRailsFocusedTest()
  ruby RubyTest.new.run_test(true)
endfunction

function s:RunRubyFocusedContext()
  ruby RubyTest.new.run_context()
endfunction

ruby << EOF
module VIM
  class Buffer
    def method_missing(method, *args, &block)
      VIM.command "#{method} #{self.name}"
    end
  end
end

class RubyTest
  def current_file
    VIM::Buffer.current.name
  end

  def rails_test_dir
    current_file.split('/')[0..-current_file.split('/').reverse.index('test')-1].join('/')
  end

  def spec_file?
    current_file =~ /spec_|_spec/
  end

  def line_number
    VIM::Buffer.current.line_number
  end

  def run_spec
    send_to_vimux("#{spec_command} #{current_file}:#{line_number}")
  end

  def run_unit_test(rails=false)
    method_name = nil

    (line_number + 1).downto(1) do |line_number|
      if VIM::Buffer.current[line_number] =~ /def (test_\w+)/
        method_name = $1
        break
      elsif VIM::Buffer.current[line_number] =~ /test "([^"]+)"/ ||
            VIM::Buffer.current[line_number] =~ /test '([^']+)'/
        method_name = "test_" + $1.split(" ").join("_")
        break
      elsif VIM::Buffer.current[line_number] =~ /should "([^"]+)"/ ||
            VIM::Buffer.current[line_number] =~ /should '([^']+)'/
        method_name = "\"/#{Regexp.escape($1)}/\""
        break
      end
    end

    send_to_vimux("#{ruby_command} #{"-I #{rails_test_dir} " if rails}#{current_file} -n #{method_name}") if method_name
  end

  def run_test(rails=false)
    if spec_file?
      run_spec
    else
      run_unit_test(rails)
    end
  end

  def run_context
    method_name = nil
    context_line_number = nil

    (line_number + 1).downto(1) do |line_number|
      if VIM::Buffer.current[line_number] =~ /(context|describe) "([^"]+)"/ ||
         VIM::Buffer.current[line_number] =~ /(context|describe) '([^']+)'/
        method_name = $2
        context_line_number = line_number
        break
      end
    end

    if method_name
      if spec_file?
        send_to_vimux("#{spec_command} #{current_file}:#{context_line_number}")
      else
        method_name = Regexp.escape(method_name)
        send_to_vimux("#{ruby_command} #{current_file} -n \"/#{method_name}/\"")
      end
    end
  end

  def run_all(rails=false)
    if spec_file?
      send_to_vimux("#{spec_command} \"#{current_file}\"")
    else
      send_to_vimux("#{ruby_command} #{"-I #{rails_test_dir} " if rails}#{current_file}")
    end
  end

  def ruby_command
    if File.exists?('./.zeus.sock')
      if current_file =~ /\/acceptance\//
        'zeus acceptance'
      else
        'zeus test'
      end
    else
      'ruby'
    end
  end


  def spec_command
    if File.exists?('./.zeus.sock')
      'zeus rspec'
    else
      'rspec'
    end
  end

  def send_to_vimux(test_command)
    Vim.command("call RunVimTmuxCommand('clear && #{test_command}')")
  end
end
EOF
