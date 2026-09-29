#!/bin/bash
# Supprime le cluster : tous les nodes (conteneurs Docker), Argo CD et l'appli disparaissent
# Les outils installés (docker, kubectl, k3d) restent sur la VM
k3d cluster delete iot-cluster