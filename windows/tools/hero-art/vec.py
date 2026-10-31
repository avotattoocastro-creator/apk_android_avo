import numpy as np, cv2, json, sys
from skimage.morphology import skeletonize, remove_small_objects
from scipy.ndimage import distance_transform_edt
from scipy.signal import savgol_filter
im=cv2.imread('/tmp/hero/avo_home_hero.jpg').astype(np.float32)
X0,Y0,X1,Y1=235,60,545,320
S=4
crop=im[Y0:Y1,X0:X1]
big=cv2.resize(crop,None,fx=S,fy=S,interpolation=cv2.INTER_CUBIC)
gray=big.mean(2)
bg=cv2.medianBlur(np.clip(gray,0,255).astype(np.uint8),61).astype(np.float32)
sat=(big.max(2)-big.min(2))
white=np.clip(gray-bg,0,255)
cv2.imwrite('white.png',np.clip(white*2,0,255).astype(np.uint8))
strong=(white>float(sys.argv[1]) if len(sys.argv)>1 else white>45)
strong=remove_small_objects(strong,min_size=60*S)
np.save('white.npy',white)
cv2.imwrite('mask.png',strong.astype(np.uint8)*255)
