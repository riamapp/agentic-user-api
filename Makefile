LAMBDA_ZIP = user_lambda.zip
BUILD_DIR  = .lambda_build

.PHONY: lambda-zip clean

lambda-zip: clean
	# Use Docker to build Lambda package with Linux-compatible dependencies
	# This ensures Pydantic v2's native extensions work correctly on Lambda
	# Use --platform to ensure x86_64 architecture (Lambda default)
	docker run --rm --platform linux/amd64 --entrypoint /bin/bash \
		-v "$(PWD):/var/task" \
		public.ecr.aws/lambda/python:3.12 \
		-c "yum install -y zip >/dev/null 2>&1 || microdnf install -y zip >/dev/null 2>&1 || true; pip install . -t $(BUILD_DIR) && cd $(BUILD_DIR) && zip -q -r ../$(LAMBDA_ZIP) ."

clean:
	rm -rf $(BUILD_DIR) $(LAMBDA_ZIP)
