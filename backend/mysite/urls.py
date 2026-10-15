"""
URL configuration for mysite project.
"""
from django.contrib import admin
from django.http import JsonResponse
from django.urls import path


def hello(request):
    return JsonResponse({"message": "Привет с Django!"})


urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/hello/', hello),
]
