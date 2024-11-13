.PHONY: demo-eks demo-gke demo-access demo-cleanup demo-refresh

demo-eks:
	@./demo/create.sh -p eks -n demo -m 5 -f

demo-gke:
	@./demo/create.sh -p gke -n demo -m 2 -f

demo-access:
	@./demo/access.sh

demo-cleanup:
	@./demo/cleanup.sh

demo-refresh:
	@./demo/refresh.sh