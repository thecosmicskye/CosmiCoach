import os
from PIL import Image, ImageDraw, ImageOps

# Define the paths
input_image_path = "source.png"
output_dir_ios = "../ADHDCoach/Assets.xcassets/AppIconIOS.appiconset"
output_dir_macos = "../ADHDCoach/Assets.xcassets/AppIconMacOS.appiconset"
launch_screen_dir = "../ADHDCoach/Assets.xcassets/LaunchScreen.imageset"

# Define the correct list of sizes for iOS and macOS app icons with scaling factors
sizes = {
    "ios": [
        {"size": (20, 20), "scales": [2, 3], "idiom": "iphone"},  # Notification
        {"size": (29, 29), "scales": [1, 2, 3], "idiom": "iphone"},  # Settings
        {"size": (40, 40), "scales": [2, 3], "idiom": "iphone"},  # Spotlight
        {"size": (60, 60), "scales": [2, 3], "idiom": "iphone"},  # App Icon
        {"size": (76, 76), "scales": [1, 2], "idiom": "ipad"},  # iPad App Icon
        {"size": (83.5, 83.5), "scales": [2], "idiom": "ipad"},  # iPad Pro App Icon
        {"size": (1024, 1024), "scales": [1], "idiom": "ios-marketing"},  # App Store
    ],
    "macos": [
        {"size": (16, 16), "scales": [1, 2], "idiom": "mac"},  # Finder Icon
        {"size": (32, 32), "scales": [1, 2], "idiom": "mac"},  # Finder Icon
        {"size": (128, 128), "scales": [1, 2], "idiom": "mac"},  # Finder Icon
        {"size": (256, 256), "scales": [1, 2], "idiom": "mac"},  # Finder Icon
        {"size": (512, 512), "scales": [1, 2], "idiom": "mac"},  # Finder Icon
    ],
}

# Ensure the output directories exist
os.makedirs(output_dir_ios, exist_ok=True)
os.makedirs(output_dir_macos, exist_ok=True)
os.makedirs(launch_screen_dir, exist_ok=True)

# Load the source image
try:
    source_image = Image.open(input_image_path)
except FileNotFoundError:
    raise FileNotFoundError(f"Source image not found at path: {input_image_path}")

# Ensure the source image is in RGBA mode (supports transparency)
if source_image.mode != "RGBA":
    source_image = source_image.convert("RGBA")

# Validate the source image size
if source_image.size[0] < 1024 or source_image.size[1] < 1024:
    raise ValueError(
        "Source image must be at least 1024x1024 pixels for production-ready icons."
    )


# Function to add rounded corners with transparent space
def add_rounded_corners(image, corner_radius):
    # Create a mask for rounded corners
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), image.size], radius=corner_radius, fill=255)

    # Apply the rounded corners mask to the image
    rounded_image = ImageOps.fit(image, mask.size, centering=(0.5, 0.5))
    rounded_image.putalpha(mask)
    return rounded_image


# Function to save the icon and create the Contents.json entry
def save_icon(size, scale, output_dir, idiom, contents, platform=None):
    icon_size = (int(size[0] * scale), int(size[1] * scale))
    icon_image = source_image.resize(icon_size, Image.LANCZOS)

    # Apply rounded corners for macOS icons
    if idiom == "mac":
        corner_radius = int(min(icon_size) * 0.2)  # 20% of the smallest dimension
        icon_image = add_rounded_corners(icon_image, corner_radius)

    icon_filename = f"{int(size[0])}x{int(size[1])}@{scale}x.png".replace(".0", "")
    icon_path = os.path.join(output_dir, icon_filename)

    # Ensure that the 512x512@2x icon is exactly 1024x1024 pixels
    if size == (512, 512) and scale == 2:
        if icon_size != (1024, 1024):
            raise ValueError("512x512@2x must be 1024x1024 pixels")

    icon_image.save(icon_path)

    image_entry = {
        "idiom": idiom,
        "size": f"{int(size[0])}x{int(size[1])}",
        "scale": f"{scale}x",
        "filename": icon_filename,
    }
    if platform:
        image_entry["platform"] = platform

    contents["images"].append(image_entry)


# Function to generate the Contents.json file
def generate_contents_json(output_dir, contents):
    contents_json_path = os.path.join(output_dir, "Contents.json")
    with open(contents_json_path, "w") as f:
        import json

        json.dump(contents, f, indent=2)
    print(f"Saved {contents_json_path}")


# Resize and save the images for iOS
contents_ios = {"images": [], "info": {"version": 1, "author": "xcode"}}
for size_info in sizes["ios"]:
    size = size_info["size"]
    scales = size_info["scales"]
    idiom = size_info["idiom"]
    platform = size_info.get("platform")
    for scale in scales:
        save_icon(size, scale, output_dir_ios, idiom, contents_ios, platform)

generate_contents_json(output_dir_ios, contents_ios)

# Resize and save the images for macOS
contents_macos = {"images": [], "info": {"version": 1, "author": "xcode"}}
for size_info in sizes["macos"]:
    size = size_info["size"]
    scales = size_info["scales"]
    idiom = size_info["idiom"]
    for scale in scales:
        save_icon(size, scale, output_dir_macos, idiom, contents_macos)

# generate_contents_json(output_dir_macos, contents_macos)


# Create the launch screen files for 1x, 2x, and 3x
def create_launch_screen(output_dir, source_image):
    # Define launch screen sizes (1x, 2x, 3x)
    screen_sizes = [(2732, 2732), (5464, 5464), (8196, 8196)]
    scale_labels = ["1x", "2x", "3x"]

    for i, screen_size in enumerate(screen_sizes):
        # Create a black background with the appropriate size
        background = Image.new("RGBA", screen_size, (0, 0, 0, 255))

        # Maintain aspect ratio and resize the source image to fit within the screen size
        source_image_resized = source_image.copy()
        source_image_resized.thumbnail(
            (screen_size[0] // 2, screen_size[1] // 2), Image.LANCZOS
        )

        # Calculate the position to center the app icon
        icon_position = (
            (background.width - source_image_resized.width) // 2,
            (background.height - source_image_resized.height) // 2,
        )

        # Paste the app icon onto the black background
        background.paste(source_image_resized, icon_position, source_image_resized)

        # Save the launch screen image with the appropriate scale label
        launch_screen_path = os.path.join(
            output_dir, f"LaunchScreen@{scale_labels[i]}.png"
        )
        background.save(launch_screen_path)
        print(f"Saved launch screen at {launch_screen_path}")


create_launch_screen(launch_screen_dir, source_image)

# Generate Contents.json for Launch Screen
launch_screen_contents = {
    "images": [
        {"idiom": "universal", "filename": "LaunchScreen@1x.png", "scale": "1x"},
        {"idiom": "universal", "filename": "LaunchScreen@2x.png", "scale": "2x"},
        {"idiom": "universal", "filename": "LaunchScreen@3x.png", "scale": "3x"},
    ],
    "info": {"version": 1, "author": "xcode"},
}
generate_contents_json(launch_screen_dir, launch_screen_contents)

print(
    "All production-ready icons and launch screens generated successfully and saved to:"
)
print(f"- {output_dir_ios}")
# print(f"- {output_dir_macos}")
print(f"- {launch_screen_dir}")
