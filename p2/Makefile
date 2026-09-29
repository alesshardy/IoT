# **************************************************************************** #
#                                  VARIABLES                                   #
# **************************************************************************** #

# COLORS
BLACK			=	\033[0;30m
RED				=	\033[0;31m
GREEN			=	\033[0;32m
YELLOW			=	\033[0;33m
BLUE			=	\033[0;34m
PURPLE			=	\033[0;35m
CYAN			=	\033[0;36m
WHITE			=	\033[0;37m

END				=	\033[0m

SERVER	:= kammiS
IP		:= 192.168.56.110
NS		:= inception-of-things
KUBECTL	:= KUBECONFIG=/home/vagrant/.kube/config kubectl

# **************************************************************************** #
#                                    RULES                                     #
# **************************************************************************** #

up:
	@printf "${YELLOW}> Starting server... ${END}\n"
	@vagrant up

destroy:
	@printf "${YELLOW}> Destroy server... ${END}\n"
	@vagrant destroy -f

status:
	@vagrant status

ssh:
	@printf "${YELLOW}> SSH into server... ${END}\n"
	@vagrant ssh ${SERVER}

pods:
	@printf "${YELLOW}> Pods (attendu: 1 + 3 + 1)... ${END}\n"
	@vagrant ssh ${SERVER} -c "${KUBECTL} get pods -n ${NS}"

svc:
	@printf "${YELLOW}> Services et endpoints... ${END}\n"
	@vagrant ssh ${SERVER} -c "${KUBECTL} get svc,endpoints -n ${NS}"

ingress:
	@printf "${YELLOW}> Ingress... ${END}\n"
	@vagrant ssh ${SERVER} -c "${KUBECTL} describe ingress apps-ingress -n ${NS}"

test:
	@printf "${YELLOW}> Host: app1.com ${END}\n"
	@curl -s -H "Host: app1.com" http://${IP}/ | grep "Hello from"
	@printf "${YELLOW}> Host: app2.com ${END}\n"
	@curl -s -H "Host: app2.com" http://${IP}/ | grep "Hello from"
	@printf "${YELLOW}> Host: nimportequoi.com (defaut) ${END}\n"
	@curl -s -H "Host: nimportequoi.com" http://${IP}/ | grep "Hello from"

.PHONY: up destroy status ssh pods svc ingress test