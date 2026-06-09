#!/usr/bin/env python3
"""
Quick test script to verify the bulk_upload endpoint is working
"""

import requests
import sys
import os

def test_api_endpoint():
    """Test if the bulk_upload endpoint exists and responds"""
    
    # Configuration
    api_url = "http://localhost:3000"
    
    print("Testing Music Archive API bulk_upload endpoint...")
    print(f"API URL: {api_url}")
    print()
    
    # Test 1: Check if the endpoint exists (should get 401 without auth)
    print("Test 1: Checking if endpoint exists...")
    try:
        response = requests.post(
            f"{api_url}/api/v1/songs/bulk_upload",
            timeout=5
        )
        
        if response.status_code == 404:
            print("❌ FAILED: Endpoint still returns 404")
            print(f"Response: {response.text[:200]}")
            return False
        elif response.status_code == 401:
            print("✅ PASSED: Endpoint exists (returns 401 unauthorized, which is expected)")
            return True
        elif response.status_code == 422:
            print("✅ PASSED: Endpoint exists (returns 422 unprocessable entity)")
            print("   This means the endpoint is working but needs authentication and file")
            return True
        else:
            print(f"⚠️  UNEXPECTED: Got status code {response.status_code}")
            print(f"Response: {response.text[:200]}")
            return True  # Endpoint exists, just unexpected response
            
    except requests.exceptions.ConnectionError:
        print("❌ FAILED: Could not connect to API")
        print("   Make sure the Archive service is running (cd archive && rails server)")
        return False
    except Exception as e:
        print(f"❌ ERROR: {e}")
        return False

if __name__ == "__main__":
    success = test_api_endpoint()
    
    print()
    if success:
        print("✅ The bulk_upload endpoint has been fixed!")
        print()
        print("Next steps:")
        print("1. Make sure the Archive service is running:")
        print("   cd archive && rails server")
        print()
        print("2. Test with your universal_upload.py script:")
        print("   python utilities/universal_upload.py <music_directory> --username <your_email> --password <your_password> --limit 1")
        print()
    else:
        print("❌ The endpoint is still not working")
        print()
        print("Please make sure:")
        print("1. The Archive service is running")
        print("2. The service was restarted after the code changes")
        
    sys.exit(0 if success else 1)

