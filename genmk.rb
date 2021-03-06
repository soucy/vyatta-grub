#! /usr/bin/ruby -w
#
# Copyright (C) 2002,2003,2004,2005,2006,2007,2008,2009  Free Software Foundation, Inc.
#
# This genmk.rb is free software; the author
# gives unlimited permission to copy and/or distribute it,
# with or without modifications, as long as this notice is preserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY, to the extent permitted by law; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE.

module Enumerable
  def collect_with_index
    ret = []
    self.each_with_index do |item, index|
      ret.push(yield(item, index))
    end
    ret
  end
end

class String
  def to_var
    self.gsub(/[^a-zA-Z0-9_@]/, '_')
  end

  def suffix(str)
    self.sub(/\.[^\.]*$/, '') + '.' + str
  end

  def to_obj
    self.sub(/\.[^\.]*$/, '').to_var + '.o'
  end
end

class Image
  def initialize(dir, name)
    @dir = dir
    @name = name
    @rule_count = 0
  end
  attr_reader :dir, :name

  def rule(sources)
    prefix = @name.to_var
    @rule_count += 1
    exe = @name.suffix('exec')
    objs = sources.collect do |src|
      raise "unknown source file `#{src}'" if /\.[cS]$/ !~ src
      prefix + '-' + src.to_obj
    end
    objs_str = objs.join(' ')
    deps = objs.collect {|obj| obj.suffix('d')}
    deps_str = deps.join(' ')

"
clean-image-#{@name}.#{@rule_count}:
	rm -f #{@name} #{exe} #{objs_str}

CLEAN_IMAGE_TARGETS += clean-image-#{@name}.#{@rule_count}

mostlyclean-image-#{@name}.#{@rule_count}:
	rm -f #{deps_str}

MOSTLYCLEAN_IMAGE_TARGETS += mostlyclean-image-#{@name}.#{@rule_count}

ifneq ($(TARGET_APPLE_CC),1)
#{@name}: #{exe}
	$(OBJCOPY) -O $(#{prefix}_FORMAT) --strip-unneeded -R .note -R .comment -R .note.gnu.build-id -R .reginfo -R .rel.dyn $< $@
else
ifneq (#{exe},kernel.exec)
#{@name}: #{exe} ./grub-macho2img
	./grub-macho2img $< $@
else
#{@name}: #{exe} ./grub-macho2img
	./grub-macho2img --bss $< $@
endif
endif

#{exe}: #{objs_str}
	$(TARGET_CC) -o $@ $^ $(TARGET_LDFLAGS) $(#{prefix}_LDFLAGS)

" + objs.collect_with_index do |obj, i|
      src = sources[i]
      fake_obj = File.basename(src).suffix('o')
      dep = deps[i]
      flag = if /\.c$/ =~ src then 'CFLAGS' else 'ASFLAGS' end
      extra_flags = if /\.S$/ =~ src then '-DASM_FILE=1' else '' end
      dir = File.dirname(src)

      "#{obj}: #{src} $(#{src}_DEPENDENCIES)
	$(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} $(TARGET_#{flag}) $(#{prefix}_#{flag}) -DGRUB_FILE=\\\"#{src}\\\" -MD -c -o $@ $<
-include #{dep}

"
    end.join('')
  end
end

# Use PModule instead Module, to avoid name conflicting.
class PModule
  def initialize(dir, name)
    @dir = dir
    @name = name
    @rule_count = 0
  end
  attr_reader :dir, :name

  def rule(sources)
    prefix = @name.to_var
    @rule_count += 1
    objs = sources.collect do |src|
      raise "unknown source file `#{src}'" if /\.[cS]$/ !~ src
      prefix + '-' + src.to_obj
    end
    objs_str = objs.join(' ')
    deps = objs.collect {|obj| obj.suffix('d')}
    deps_str = deps.join(' ')
    pre_obj = 'pre-' + @name.suffix('o')
    mod_src = 'mod-' + @name.suffix('c')
    mod_obj = mod_src.suffix('o')
    defsym = 'def-' + @name.suffix('lst')
    undsym = 'und-' + @name.suffix('lst')
    mod_name = File.basename(@name, '.mod')
    symbolic_name = mod_name.sub(/\.[^\.]*$/, '')

"
clean-module-#{@name}.#{@rule_count}:
	rm -f #{@name} #{mod_obj} #{mod_src} #{pre_obj} #{objs_str} #{undsym}

CLEAN_MODULE_TARGETS += clean-module-#{@name}.#{@rule_count}

clean-module-#{@name}-symbol.#{@rule_count}:
	rm -f #{defsym}

CLEAN_MODULE_TARGETS += clean-module-#{@name}-symbol.#{@rule_count}
DEFSYMFILES += #{defsym}
mostlyclean-module-#{@name}.#{@rule_count}:
	rm -f #{deps_str}

MOSTLYCLEAN_MODULE_TARGETS += mostlyclean-module-#{@name}.#{@rule_count}
UNDSYMFILES += #{undsym}

ifeq ($(TARGET_NO_MODULES), yes)
#{@name}: #{pre_obj} $(TARGET_OBJ2ELF)
	-rm -f $@
	$(TARGET_CC) $(#{prefix}_LDFLAGS) $(TARGET_LDFLAGS) -Wl,-r,-d -o $@ #{pre_obj}
	if test ! -z \"$(TARGET_OBJ2ELF)\"; then ./$(TARGET_OBJ2ELF) $@ || (rm -f $@; exit 1); fi
	if test x$(TARGET_NO_STRIP) != xyes ; then $(STRIP) --strip-unneeded -K grub_mod_init -K grub_mod_fini -K _grub_mod_init -K _grub_mod_fini -R .note -R .comment $@; fi
else
ifneq ($(TARGET_APPLE_CC),1)
#{@name}: #{pre_obj} #{mod_obj} $(TARGET_OBJ2ELF)
	-rm -f $@
	$(TARGET_CC) $(#{prefix}_LDFLAGS) $(TARGET_LDFLAGS) -Wl,-r,-d -o $@ #{pre_obj} #{mod_obj}
	if test ! -z \"$(TARGET_OBJ2ELF)\"; then ./$(TARGET_OBJ2ELF) $@ || (rm -f $@; exit 1); fi
	if test x$(TARGET_NO_STRIP) != xyes ; then $(STRIP) --strip-unneeded -K grub_mod_init -K grub_mod_fini -K _grub_mod_init -K _grub_mod_fini -R .note -R .comment $@; fi
else
#{@name}: #{pre_obj} #{mod_obj} $(TARGET_OBJ2ELF)
	-rm -f $@
	-rm -f $@.bin
	$(TARGET_CC) $(#{prefix}_LDFLAGS) $(TARGET_LDFLAGS) -Wl,-r,-d -o $@.bin #{pre_obj} #{mod_obj}
	$(OBJCONV) -f$(TARGET_MODULE_FORMAT) -nr:_grub_mod_init:grub_mod_init -nr:_grub_mod_fini:grub_mod_fini -wd1106 -ew2030 -ew2050 -nu -nd $@.bin $@
	-rm -f $@.bin
endif
endif

#{pre_obj}: $(#{prefix}_DEPENDENCIES) #{objs_str}
	-rm -f $@
	$(TARGET_CC) $(#{prefix}_LDFLAGS) $(TARGET_LDFLAGS) -Wl,-r,-d -o $@ #{objs_str}

#{mod_obj}: #{mod_src}
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) $(#{prefix}_CFLAGS) -DGRUB_FILE=\\\"#{mod_src}\\\" -c -o $@ $<

#{mod_src}: $(builddir)/moddep.lst $(srcdir)/genmodsrc.sh
	sh $(srcdir)/genmodsrc.sh '#{mod_name}' $< > $@ || (rm -f $@; exit 1)

ifneq ($(TARGET_APPLE_CC),1)
#{defsym}: #{pre_obj}
	$(NM) -g --defined-only -P -p $< | sed 's/^\\([^ ]*\\).*/\\1 #{mod_name}/' > $@
else
#{defsym}: #{pre_obj}
	$(NM) -g -P -p $< | grep -E '^[a-zA-Z0-9_]* [TDS]'  | sed 's/^\\([^ ]*\\).*/\\1 #{mod_name}/' > $@
endif

#{undsym}: #{pre_obj}
	echo '#{mod_name}' > $@
	$(NM) -u -P -p $< | cut -f1 -d' ' >> $@

" + objs.collect_with_index do |obj, i|
      src = sources[i]
      fake_obj = File.basename(src).suffix('o')
      extra_target = obj.sub(/\.[^\.]*$/, '') + '-extra'
      command = 'cmd-' + obj.suffix('lst')
      fs = 'fs-' + obj.suffix('lst')
      partmap = 'partmap-' + obj.suffix('lst')
      handler = 'handler-' + obj.suffix('lst')
      terminal = 'terminal-' + obj.suffix('lst')
      parttool = 'parttool-' + obj.suffix('lst')
      video = 'video-' + obj.suffix('lst')
      dep = deps[i]
      flag = if /\.c$/ =~ src then 'CFLAGS' else 'ASFLAGS' end
      extra_flags = if /\.S$/ =~ src then '-DASM_FILE=1' else '' end
      dir = File.dirname(src)

      "#{obj}: #{src} $(#{src}_DEPENDENCIES)
	$(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} $(TARGET_#{flag}) $(#{prefix}_#{flag}) -DGRUB_FILE=\\\"#{src}\\\" -MD -c -o $@ $<
-include #{dep}

clean-module-#{extra_target}.#{@rule_count}:
	rm -f #{command} #{fs} #{partmap} #{handler} #{parttool} #{video} #{terminal}

CLEAN_MODULE_TARGETS += clean-module-#{extra_target}.#{@rule_count}

COMMANDFILES += #{command}
FSFILES += #{fs}
PARTTOOLFILES += #{parttool}
PARTMAPFILES += #{partmap}
HANDLERFILES += #{handler}
TERMINALFILES += #{terminal}
VIDEOFILES += #{video}

#{command}: #{src} $(#{src}_DEPENDENCIES) gencmdlist.sh
	set -e; \
	  $(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} $(TARGET_#{flag}) $(#{prefix}_#{flag}) -E $< \
	  | sh $(srcdir)/gencmdlist.sh #{symbolic_name} > $@ || (rm -f $@; exit 1)

#{fs}: #{src} $(#{src}_DEPENDENCIES) genfslist.sh
	set -e; \
	  $(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} -DGRUB_LST_GENERATOR $(TARGET_#{flag}) $(#{prefix}_#{flag}) -E $< \
	  | sh $(srcdir)/genfslist.sh #{symbolic_name} > $@ || (rm -f $@; exit 1)

#{parttool}: #{src} $(#{src}_DEPENDENCIES) genparttoollist.sh
	set -e; \
	  $(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} $(TARGET_#{flag}) $(#{prefix}_#{flag}) -E $< \
	  | sh $(srcdir)/genparttoollist.sh #{symbolic_name} > $@ || (rm -f $@; exit 1)

#{partmap}: #{src} $(#{src}_DEPENDENCIES) genpartmaplist.sh
	set -e; \
	  $(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} -DGRUB_LST_GENERATOR $(TARGET_#{flag}) $(#{prefix}_#{flag}) -E $< \
	  | sh $(srcdir)/genpartmaplist.sh #{symbolic_name} > $@ || (rm -f $@; exit 1)

#{handler}: #{src} $(#{src}_DEPENDENCIES) genhandlerlist.sh
	set -e; \
	  $(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} $(TARGET_#{flag}) $(#{prefix}_#{flag}) -E $< \
	  | sh $(srcdir)/genhandlerlist.sh #{symbolic_name} > $@ || (rm -f $@; exit 1)

#{terminal}: #{src} $(#{src}_DEPENDENCIES) genterminallist.sh
	set -e; \
	  $(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} $(TARGET_#{flag}) $(#{prefix}_#{flag}) -E $< \
	  | sh $(srcdir)/genterminallist.sh #{symbolic_name} > $@ || (rm -f $@; exit 1)

#{video}: #{src} $(#{src}_DEPENDENCIES) genvideolist.sh
	set -e; \
	  $(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} -DGRUB_LST_GENERATOR $(TARGET_#{flag}) $(#{prefix}_#{flag}) -E $< \
	  | sh $(srcdir)/genvideolist.sh #{symbolic_name} > $@ || (rm -f $@; exit 1)

"
    end.join('')
  end
end

class Utility
  def initialize(dir, name)
    @dir = dir
    @name = name
    @rule_count = 0
  end
  def print_tail()
    prefix = @name.to_var
    print "#{@name}: $(#{prefix}_DEPENDENCIES) $(#{prefix}_OBJECTS)
	$(CC) -o $@ $(#{prefix}_OBJECTS) $(LDFLAGS) $(#{prefix}_LDFLAGS)

"
  end
  attr_reader :dir, :name

  def rule(sources)
    prefix = @name.to_var
    @rule_count += 1
    objs = sources.collect do |src|
      raise "unknown source file `#{src}'" if /\.[cS]$/ !~ src
      prefix + '-' + src.to_obj
    end
    objs_str = objs.join(' ');
    deps = objs.collect {|obj| obj.suffix('d')}
    deps_str = deps.join(' ');

    "
clean-utility-#{@name}.#{@rule_count}:
	rm -f #{@name}$(EXEEXT) #{objs_str}

CLEAN_UTILITY_TARGETS += clean-utility-#{@name}.#{@rule_count}

mostlyclean-utility-#{@name}.#{@rule_count}:
	rm -f #{deps_str}

MOSTLYCLEAN_UTILITY_TARGETS += mostlyclean-utility-#{@name}.#{@rule_count}

#{prefix}_OBJECTS += #{objs_str}

" + objs.collect_with_index do |obj, i|
      src = sources[i]
      fake_obj = File.basename(src).suffix('o')
      dep = deps[i]
      dir = File.dirname(src)

      "#{obj}: #{src} $(#{src}_DEPENDENCIES)
	$(CC) -I#{dir} -I$(srcdir)/#{dir} $(CPPFLAGS) $(CFLAGS) -DGRUB_UTIL=1 $(#{prefix}_CFLAGS) -DGRUB_FILE=\\\"#{src}\\\" -MD -c -o $@ $<
-include #{dep}

"
    end.join('')
  end
end

class Program
  def initialize(dir, name)
    @dir = dir
    @name = name
  end
  attr_reader :dir, :name

  def print_tail()
    prefix = @name.to_var
    print "CLEANFILES += #{@name} $(#{prefix}_OBJECTS)
ifeq ($(#{prefix}_RELOCATABLE),yes)
#{@name}: $(#{prefix}_DEPENDENCIES) $(#{prefix}_OBJECTS)
	$(TARGET_CC) -Wl,-r,-d -o $@ $(#{prefix}_OBJECTS) $(TARGET_LDFLAGS) $(#{prefix}_LDFLAGS)
	if test x$(TARGET_NO_STRIP) != xyes ; then $(STRIP) --strip-unneeded -K start -R .note -R .comment $@; fi
else
#{@name}: $(#{prefix}_DEPENDENCIES) $(#{prefix}_OBJECTS)
	$(TARGET_CC) -o $@ $(#{prefix}_OBJECTS) $(TARGET_LDFLAGS) $(#{prefix}_LDFLAGS)
	if test x$(TARGET_NO_STRIP) != xyes ; then $(STRIP) -R .rel.dyn -R .reginfo -R .note -R .comment $@; fi
endif

"
  end

  def rule(sources)
    prefix = @name.to_var
    objs = sources.collect do |src|
      raise "unknown source file `#{src}'" if /\.[cS]$/ !~ src
      prefix + '-' + src.to_obj
    end
    deps = objs.collect {|obj| obj.suffix('d')}
    deps_str = deps.join(' ');

    "MOSTLYCLEANFILES += #{deps_str}

" + objs.collect_with_index do |obj, i|
      src = sources[i]
      fake_obj = File.basename(src).suffix('o')
      dep = deps[i]
      flag = if /\.c$/ =~ src then 'CFLAGS' else 'ASFLAGS' end
      extra_flags = if /\.S$/ =~ src then '-DASM_FILE=1' else '' end
      dir = File.dirname(src)

      "#{obj}: #{src} $(#{src}_DEPENDENCIES)
	$(TARGET_CC) -I#{dir} -I$(srcdir)/#{dir} $(TARGET_CPPFLAGS) #{extra_flags} $(TARGET_#{flag}) $(#{prefix}_#{flag}) -DGRUB_FILE=\\\"#{src}\\\" -MD -c -o $@ $<

-include #{dep}

#{prefix}_OBJECTS += #{obj}
"
    end.join('')
  end
end

class Script
  def initialize(dir, name)
    @dir = dir
    @name = name
  end
  attr_reader :dir, :name

  def rule(sources)
    if sources.length != 1
      raise "only a single source file must be specified for a script"
    end
    src = sources[0]
    if /\.in$/ !~ src
      raise "unknown source file `#{src}'"
    end

    "CLEANFILES += #{@name}

#{@name}: #{src} $(#{src}_DEPENDENCIES) config.status
	./config.status --file=-:#{src} | sed -e 's,@pkglib_DATA@,$(pkglib_DATA),g' > $@
	chmod +x $@

"
  end
end

images = []
utils = []
pmodules = []
programs = []
scripts = []

l = gets
print l
print "# Generated by genmk.rb, please don't edit!\n"

cont = false
str = nil
while l = gets
  if cont
    str += l
  else
    str = l
  end

  print l
  cont = (/\\$/ =~ l)
  unless cont
    str.gsub!(/\\\n/, ' ')

    if /^([a-zA-Z0-9_]+)\s*\+?=\s*(.*?)\s*$/ =~ str
      var, args = $1, $2

      if var =~ /^([a-zA-Z0-9_]+)_([A-Z]+)$/
	prefix, type = $1, $2

	case type
	when 'IMAGES'
	  images += args.split(/\s+/).collect do |img|
	    Image.new(prefix, img)
	  end

	when 'MODULES'
	  pmodules += args.split(/\s+/).collect do |pmod|
	    PModule.new(prefix, pmod)
	  end

	when 'UTILITIES'
	  utils += args.split(/\s+/).collect do |util|
	    Utility.new(prefix, util)
	  end

	when 'PROGRAMS'
	  programs += args.split(/\s+/).collect do |prog|
	    Program.new(prefix, prog)
	  end

	when 'SCRIPTS'
	  scripts += args.split(/\s+/).collect do |script|
	    Script.new(prefix, script)
	  end

	when 'SOURCES'
	  if img = images.detect() {|i| i.name.to_var == prefix}
	    print img.rule(args.split(/\s+/))
	  elsif pmod = pmodules.detect() {|m| m.name.to_var == prefix}
	    print pmod.rule(args.split(/\s+/))
	  elsif util = utils.detect() {|u| u.name.to_var == prefix}
	    print util.rule(args.split(/\s+/))
	  elsif program = programs.detect() {|u| u.name.to_var == prefix}
	    print program.rule(args.split(/\s+/))
	  elsif script = scripts.detect() {|s| s.name.to_var == prefix}
	    print script.rule(args.split(/\s+/))
	  end
	end
      end

    end

  end

end
utils.each {|util| util.print_tail()}
programs.each {|program| program.print_tail()}

