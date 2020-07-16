from __future__ import print_function


def get_images():
    file = open("Manifest", "r")
    images = {}
    for line in file:
        values = line.split()
        if len(values) < 2:
            continue
        key = values[0].lower()
        images[key] = {
            'name': values[1],
            'id': values[2] if len(values) > 2 else '',
        }
    file.close()
    return images
