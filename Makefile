.PHONY: validate test-vm clean-test-vm shellcheck help

YAML := autoinstall-desktop.yaml
TEST_VM := intunbuntu-test-$(shell date +%s)
KEY := vm_prepare_files/id_ed25519
PY := /usr/bin/python3

help:
	@echo "Targets:"
	@echo "  validate       - Static checks: yaml, cloud-init schema, late-commands shell syntax"
	@echo "  shellcheck     - Lint all *.sh scripts"
	@echo "  test-vm        - Create a throwaway VM to fully test autoinstall"
	@echo "  clean-test-vm  - Destroy the throwaway VM"

validate:
	@echo "==> YAML syntax"
	@$(PY) -c "import yaml; yaml.safe_load(open('$(YAML)'))" && echo "OK"
	@echo "==> cloud-init schema"
	@cloud-init schema --config-file $(YAML)
	@echo "==> late-commands bash syntax"
	@$(PY) -c "\
import yaml, subprocess, sys; \
ai = yaml.safe_load(open('$(YAML)'))['autoinstall']; \
fails = 0; \
[fails := fails + (0 if subprocess.run(['bash','-n'],input=c.split(\"sh -c '\",1)[1].rsplit(\"'\",1)[0],capture_output=True,text=True).returncode == 0 else 1) for c in ai.get('late-commands',[]) if isinstance(c,str) and \"sh -c '\" in c]; \
sys.exit(fails)" && echo "OK"

shellcheck:
	@command -v shellcheck >/dev/null || { echo "install shellcheck first"; exit 1; }
	shellcheck *.sh

test-vm:
	./create-intunbuntu-vm.sh \
	  --vm-name $(TEST_VM) \
	  --disk-pin 345721 \
	  --user-password 'M2!sQ8@vT5#LdR'
	@echo "VM $(TEST_VM) created. Destroy with: make clean-test-vm TEST_VM=$(TEST_VM)"

clean-test-vm:
	virsh -c qemu:///system destroy $(TEST_VM) 2>/dev/null || true
	virsh -c qemu:///system undefine $(TEST_VM) --remove-all-storage --nvram
