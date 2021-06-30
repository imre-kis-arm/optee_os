link-script$(sm) = $(sp-dev-kit-dir$(sm))/src/sp.ld.S
link-script-pp$(sm) = $(link-out-dir$(sm))/sp.lds
link-script-dep$(sm) = $(link-out-dir$(sm))/.sp.ld.d

SP_SIGN_ENC ?= $(PYTHON3) $(sp-dev-kit-dir$(sm))/scripts/sign_encrypt.py
SP_SIGN_KEY ?= $(sp-dev-kit-dir$(sm))/keys/default_sp.pem

ifeq ($(CFG_ENCRYPT_SP),y)
# Default SP encryption key is a dummy key derived from default
# hardware unique key (an array of 16 zero bytes) to demonstrate
# usage of REE-FS SPs encryption feature.
#
# Note that a user of this SP encryption feature needs to provide
# encryption key and its handling corresponding to their security
# requirements.
SP_ENC_KEY ?= 'b64d239b1f3c7d3b06506229cd8ff7c8af2bb4db2168621ac62c84948468c4f4'
endif

all: $(link-out-dir$(sm))/$(sp-uuid).dmp \
	$(link-out-dir$(sm))/$(sp-uuid).stripped.elf \
	$(link-out-dir$(sm))/$(sp-uuid).sp
cleanfiles += $(link-out-dir$(sm))/$(sp-uuid).elf
cleanfiles += $(link-out-dir$(sm))/$(sp-uuid).dmp
cleanfiles += $(link-out-dir$(sm))/$(sp-uuid).map
cleanfiles += $(link-out-dir$(sm))/$(sp-uuid).stripped.elf
cleanfiles += $(link-out-dir$(sm))/$(sp-uuid).sp
cleanfiles += $(link-script-pp$(sm)) $(link-script-dep$(sm))

link-ldflags  = -e__sp_entry -pie
link-ldflags += -T $(link-script-pp$(sm))
link-ldflags += -Map=$(link-out-dir$(sm))/$(sp-uuid).map
link-ldflags += --sort-section=alignment
link-ldflags += -z max-page-size=4096 # OP-TEE always uses 4K alignment
link-ldflags += --as-needed # Do not add dependency on unused shlib
link-ldflags += $(link-ldflags$(sm))

$(link-out-dir$(sm))/dyn_list:
	@$(cmd-echo-silent) '  GEN     $@'
	$(q)mkdir -p $(dir $@)
	$(q)echo "{" >$@
	$(q)echo "__elf_phdr_info;" >>$@
ifeq ($(CFG_FTRACE_SUPPORT),y)
	$(q)echo "__ftrace_info;" >>$@
endif
	$(q)echo "trace_ext_prefix;" >>$@
	$(q)echo "trace_level;" >>$@
	$(q)echo "};" >>$@
link-ldflags += --dynamic-list $(link-out-dir$(sm))/dyn_list
dynlistdep = $(link-out-dir$(sm))/dyn_list
cleanfiles += $(link-out-dir$(sm))/dyn_list

link-ldadd  = $(sp-ldadd) $(addprefix -L,$(libdirs))
link-ldadd += --start-group
link-ldadd += $(addprefix -l,$(libnames))
ifneq (,$(filter %.cpp,$(srcs)))
link-ldflags += --eh-frame-hdr
link-ldadd += $(libstdc++$(sm)) $(libgcc_eh$(sm))
endif
link-ldadd += --end-group

link-ldadd-after-libgcc += $(addprefix -l,$(libnames-after-libgcc))

ldargs-$(sp-uuid).elf := $(link-ldflags) $(objs) $(link-ldadd) \
				$(libgcc$(sm)) $(link-ldadd-after-libgcc)

link-script-cppflags-$(sm) := \
	$(filter-out $(CPPFLAGS_REMOVE) $(cppflags-remove), \
		$(nostdinc$(sm)) $(CPPFLAGS) \
		$(addprefix -I,$(incdirs$(sm)) $(link-out-dir$(sm))) \
		$(cppflags$(sm)))

-include $(link-script-dep$(sm))

link-script-pp-makefiles$(sm) = $(filter-out %.d %.cmd,$(MAKEFILE_LIST))

define gen-link-t
$(link-script-pp$(sm)): $(link-script$(sm)) $(conf-file) $(link-script-pp-makefiles$(sm))
	@$(cmd-echo-silent) '  CPP     $$@'
	$(q)mkdir -p $$(dir $$@)
	$(q)$(CPP$(sm)) -P -MT $$@ -MD -MF $(link-script-dep$(sm)) \
		$(link-script-cppflags-$(sm)) $$< -o $$@

$(link-out-dir$(sm))/$(sp-uuid).elf: $(objs) $(libdeps) \
					  $(libdeps-after-libgcc) \
					  $(link-script-pp$(sm)) \
					  $(dynlistdep) \
					  $(additional-link-deps)
	@$(cmd-echo-silent) '  LD      $$@'
	$(q)$(LD$(sm)) $(ldargs-$(sp-uuid).elf) -o $$@

$(link-out-dir$(sm))/$(sp-uuid).dmp: \
			$(link-out-dir$(sm))/$(sp-uuid).elf
	@$(cmd-echo-silent) '  OBJDUMP $$@'
	$(q)$(OBJDUMP$(sm)) -l -x -d $$< > $$@

$(link-out-dir$(sm))/$(sp-uuid).stripped.elf: \
			$(link-out-dir$(sm))/$(sp-uuid).elf
	@$(cmd-echo-silent) '  OBJCOPY $$@'
	$(q)$(OBJCOPY$(sm)) --strip-unneeded $$< $$@

cmd-echo$(sp-uuid) := SIGN   #
ifeq ($(CFG_ENCRYPT_SP),y)
crypt-args$(sp-uuid) := --enc-key $(SP_ENC_KEY)
cmd-echo$(sp-uuid) := SIGNENC
endif
$(link-out-dir$(sm))/$(sp-uuid).sp: \
			$(link-out-dir$(sm))/$(sp-uuid).stripped.elf \
			$(SP_SIGN_KEY) \
			$(lastword $(SIGN_ENC))
	@$(cmd-echo-silent) '  $$(cmd-echo$(sp-uuid)) $$@'
	$(q)$(SP_SIGN_ENC) --key $(SP_SIGN_KEY) $$(crypt-args$(sp-uuid)) \
		--uuid $(sp-uuid) --ta-version $(sp-version) \
		--in $$< --out $$@
endef

$(eval $(call gen-link-t))

additional-link-deps :=
